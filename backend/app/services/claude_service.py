import asyncio
import json
import os
import re
import shutil
from pathlib import Path
from typing import Optional, List, Dict, Any, AsyncGenerator
import logging
import yaml

from ..config import get_settings
from ..models import ClaudeSettings
from .workspace import WorkspaceService

settings = get_settings()
logger = logging.getLogger(__name__)

# Check for available sandboxing tools
FIREJAIL_AVAILABLE = shutil.which("firejail") is not None
BWRAP_AVAILABLE = shutil.which("bwrap") is not None  # bubblewrap


class ClaudeService:
    """Service for interacting with Claude Code CLI."""

    def __init__(self, user_id: str):
        self.user_id = user_id
        self.workspace = settings.get_user_workspace(user_id)
        self.claude_config = settings.get_user_claude_config_path(user_id)

    async def get_api_key(self) -> Optional[str]:
        """Get the user's API key."""
        return await WorkspaceService.get_api_key(self.user_id)

    def _build_sandboxed_command(
        self,
        cmd: List[str],
        allowed_paths: List[Path],
        readonly_paths: Optional[List[Path]] = None,
    ) -> List[str]:
        """
        Wrap a command with sandbox restrictions.

        Security: This ensures Claude CLI can ONLY access specified paths.
        Users cannot escape their workspace or access other users' files.
        """
        readonly_paths = readonly_paths or []

        if FIREJAIL_AVAILABLE:
            # Firejail provides robust sandboxing
            sandbox_cmd = [
                "firejail",
                "--quiet",
                "--noprofile",
                "--private-dev",           # Isolate /dev
                "--private-tmp",            # Isolate /tmp
                "--noroot",                 # No root privileges
                "--nosound",                # No sound
                "--no3d",                   # No 3D
                "--nodvd",                  # No DVD
                "--notv",                   # No TV
                "--nou2f",                  # No U2F
                "--novideo",                # No video
            ]

            # Whitelist allowed paths (read-write)
            for path in allowed_paths:
                sandbox_cmd.extend(["--whitelist", str(path)])

            # Whitelist readonly paths
            for path in readonly_paths:
                sandbox_cmd.extend(["--read-only", str(path)])

            # Block everything else
            sandbox_cmd.append("--private")

            sandbox_cmd.extend(cmd)
            return sandbox_cmd

        elif BWRAP_AVAILABLE:
            # Bubblewrap (used by Flatpak) - lighter alternative
            sandbox_cmd = [
                "bwrap",
                "--unshare-all",            # Unshare all namespaces
                "--die-with-parent",        # Die when parent dies
                "--dev", "/dev",            # Minimal /dev
                "--proc", "/proc",          # /proc
                "--tmpfs", "/tmp",          # Isolated /tmp
            ]

            # Bind allowed paths
            for path in allowed_paths:
                sandbox_cmd.extend(["--bind", str(path), str(path)])

            # Bind readonly paths
            for path in readonly_paths:
                sandbox_cmd.extend(["--ro-bind", str(path), str(path)])

            # Need basic system libraries
            sandbox_cmd.extend([
                "--ro-bind", "/usr", "/usr",
                "--ro-bind", "/lib", "/lib",
                "--ro-bind", "/lib64", "/lib64",
                "--ro-bind", "/bin", "/bin",
                "--ro-bind", "/etc/resolv.conf", "/etc/resolv.conf",
                "--ro-bind", "/etc/ssl", "/etc/ssl",
                "--ro-bind", "/etc/ca-certificates", "/etc/ca-certificates",
            ])

            sandbox_cmd.extend(cmd)
            return sandbox_cmd
        else:
            # No sandboxing available
            if settings.require_sandbox:
                raise RuntimeError(
                    "SECURITY ERROR: Sandboxing required but no sandbox tool available. "
                    "Install firejail: apt install firejail, or bubblewrap: apt install bubblewrap. "
                    "Set REQUIRE_SANDBOX=false to disable (NOT RECOMMENDED)."
                )
            logger.warning(
                "SECURITY WARNING: No sandbox (firejail/bwrap) available! "
                "Claude CLI runs without isolation. Install firejail: apt install firejail"
            )
            return cmd

    async def send_message(
        self,
        message: str,
        project_id: Optional[str] = None,
        continue_conversation: bool = False,
    ) -> Dict[str, Any]:
        """
        Send a message to Claude Code and get a response.

        Args:
            message: The message to send
            project_id: Optional project to focus on
            continue_conversation: Whether to continue previous conversation

        Returns:
            Dict with response, files_modified, and suggested_commands
        """
        # Determine working directory
        if project_id:
            cwd = settings.get_project_path(self.user_id, project_id)
        else:
            cwd = self.workspace

        # Build command
        cmd = [settings.claude_binary]

        # Add message via stdin with --print flag for non-interactive output
        cmd.extend(["--print", "-p", message])

        # Bypass permission prompts - safe because we sandbox with firejail
        cmd.append("--permission-mode")
        cmd.append("bypassPermissions")

        # If continuing conversation, add continue flag
        if continue_conversation:
            cmd.append("--continue")

        try:
            # Build environment with API key
            env = {**os.environ, "CLAUDE_CONFIG_DIR": str(self.claude_config)}
            api_key = await self.get_api_key()
            if api_key:
                env["ANTHROPIC_API_KEY"] = api_key

            # SECURITY: Sandbox the command to restrict file system access
            # Only allow access to:
            # - The user's workspace (read-write)
            # - The claude config directory (read-write)
            # - The specific project directory if specified (read-write)
            allowed_paths = [self.workspace, self.claude_config]
            if project_id:
                allowed_paths.append(cwd)

            sandboxed_cmd = self._build_sandboxed_command(
                cmd,
                allowed_paths=allowed_paths,
            )

            process = await asyncio.create_subprocess_exec(
                *sandboxed_cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=str(cwd),
                env=env,
            )

            stdout, stderr = await asyncio.wait_for(
                process.communicate(),
                timeout=300  # 5 minute timeout
            )

            response_text = stdout.decode("utf-8")

            # Parse the response to extract useful info
            result = {
                "response": response_text,
                "files_modified": self._extract_modified_files(response_text),
                "suggested_commands": self._extract_commands(response_text),
            }

            if stderr:
                logger.warning(f"Claude stderr: {stderr.decode('utf-8')}")

            return result

        except asyncio.TimeoutError:
            raise Exception("Claude request timed out")
        except Exception as e:
            logger.error(f"Error calling Claude: {e}")
            raise

    async def send_message_stream(
        self,
        message: str,
        project_id: Optional[str] = None,
        continue_conversation: bool = False,
    ) -> AsyncGenerator[str, None]:
        """
        Send a message to Claude Code and stream the response.

        Yields JSON strings with either 'text' chunks or final 'done' message.
        """
        # Determine working directory
        if project_id:
            cwd = settings.get_project_path(self.user_id, project_id)
        else:
            cwd = self.workspace

        # Build command
        cmd = [settings.claude_binary]
        cmd.extend(["--print", "-p", message])

        # Bypass permission prompts - safe because we sandbox with firejail
        cmd.append("--permission-mode")
        cmd.append("bypassPermissions")

        if continue_conversation:
            cmd.append("--continue")

        try:
            # Build environment with API key
            env = {**os.environ, "CLAUDE_CONFIG_DIR": str(self.claude_config)}
            api_key = await self.get_api_key()
            if api_key:
                env["ANTHROPIC_API_KEY"] = api_key

            # Sandbox the command
            allowed_paths = [self.workspace, self.claude_config]
            if project_id:
                allowed_paths.append(cwd)

            sandboxed_cmd = self._build_sandboxed_command(
                cmd,
                allowed_paths=allowed_paths,
            )

            process = await asyncio.create_subprocess_exec(
                *sandboxed_cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=str(cwd),
                env=env,
            )

            full_response = ""

            # Read stdout line by line and yield chunks
            while True:
                try:
                    # Read a chunk (up to 1KB at a time for responsiveness)
                    chunk = await asyncio.wait_for(
                        process.stdout.read(1024),
                        timeout=300
                    )
                    if not chunk:
                        break

                    text = chunk.decode("utf-8", errors="replace")
                    full_response += text

                    # Yield the text chunk
                    yield json.dumps({"text": text})

                except asyncio.TimeoutError:
                    yield json.dumps({"error": "Response timed out"})
                    break

            # Wait for process to complete
            await process.wait()

            # Read any stderr
            stderr = await process.stderr.read()
            if stderr:
                logger.warning(f"Claude stderr: {stderr.decode('utf-8')}")

            # Send final message with metadata
            yield json.dumps({
                "done": True,
                "files_modified": self._extract_modified_files(full_response),
                "suggested_commands": self._extract_commands(full_response),
            })

        except Exception as e:
            logger.error(f"Error streaming Claude response: {e}")
            yield json.dumps({"error": str(e)})

    async def get_available_models(self) -> List[str]:
        """Get list of available Claude models."""
        # These are the known Claude models
        # In a real implementation, you might query the CLI or an API
        return [
            "claude-sonnet-4-20250514",
            "claude-opus-4-20250514",
            "claude-3-5-sonnet-20241022",
            "claude-3-5-haiku-20241022",
            "claude-3-opus-20240229",
        ]

    async def list_plugins(self) -> List[Dict[str, Any]]:
        """List installed plugins/MCP servers."""
        plugins = []

        # Check for MCP config file
        mcp_config = self.claude_config / "claude_desktop_config.json"
        if mcp_config.exists():
            try:
                with open(mcp_config, "r") as f:
                    config = json.load(f)
                    for name, server in config.get("mcpServers", {}).items():
                        plugins.append({
                            "name": name,
                            "command": server.get("command", ""),
                            "enabled": True,
                            "installed": True,
                        })
            except Exception as e:
                logger.error(f"Error reading MCP config: {e}")

        return plugins

    async def search_plugins(self, query: str) -> List[Dict[str, Any]]:
        """
        Search for available plugins/MCP servers.
        This is a placeholder - in production you'd query a registry.
        """
        # Example well-known MCP servers
        available = [
            {
                "name": "filesystem",
                "description": "File system operations",
                "package": "@modelcontextprotocol/server-filesystem",
            },
            {
                "name": "github",
                "description": "GitHub API integration",
                "package": "@modelcontextprotocol/server-github",
            },
            {
                "name": "postgres",
                "description": "PostgreSQL database access",
                "package": "@modelcontextprotocol/server-postgres",
            },
            {
                "name": "sqlite",
                "description": "SQLite database access",
                "package": "@modelcontextprotocol/server-sqlite",
            },
            {
                "name": "puppeteer",
                "description": "Browser automation",
                "package": "@modelcontextprotocol/server-puppeteer",
            },
        ]

        query_lower = query.lower()
        return [p for p in available if query_lower in p["name"].lower()
                or query_lower in p.get("description", "").lower()]

    async def install_plugin(self, name: str, package: Optional[str] = None) -> bool:
        """Install an MCP server plugin."""
        # This would typically involve:
        # 1. npm install the package
        # 2. Update the MCP config

        mcp_config_path = self.claude_config / "claude_desktop_config.json"

        # Ensure directory exists
        self.claude_config.mkdir(parents=True, exist_ok=True)

        # Load or create config
        if mcp_config_path.exists():
            with open(mcp_config_path, "r") as f:
                config = json.load(f)
        else:
            config = {"mcpServers": {}}

        # Add the server (simplified - real implementation would npm install)
        config["mcpServers"][name] = {
            "command": "npx",
            "args": ["-y", package or f"@modelcontextprotocol/server-{name}"],
        }

        with open(mcp_config_path, "w") as f:
            json.dump(config, f, indent=2)

        return True

    async def uninstall_plugin(self, name: str) -> bool:
        """Uninstall an MCP server plugin."""
        mcp_config_path = self.claude_config / "claude_desktop_config.json"

        if not mcp_config_path.exists():
            return False

        with open(mcp_config_path, "r") as f:
            config = json.load(f)

        if name in config.get("mcpServers", {}):
            del config["mcpServers"][name]
            with open(mcp_config_path, "w") as f:
                json.dump(config, f, indent=2)
            return True

        return False

    async def toggle_plugin(self, name: str, enabled: bool) -> bool:
        """Enable or disable a plugin."""
        # For MCP servers, we could add a "disabled" key
        # or move to a "disabledServers" section
        mcp_config_path = self.claude_config / "claude_desktop_config.json"

        if not mcp_config_path.exists():
            return False

        with open(mcp_config_path, "r") as f:
            config = json.load(f)

        if name not in config.get("mcpServers", {}):
            return False

        # Add disabled flag
        config["mcpServers"][name]["disabled"] = not enabled

        with open(mcp_config_path, "w") as f:
            json.dump(config, f, indent=2)

        return True

    def _extract_modified_files(self, response: str) -> List[str]:
        """Extract file paths that were modified from Claude's response."""
        files = []
        # Look for common patterns in Claude's output
        patterns = [
            r"(?:Created|Modified|Updated|Wrote to|Writing to)\s+[`']?([^`'\n]+)[`']?",
            r"File:\s*([^\n]+)",
        ]
        for pattern in patterns:
            matches = re.findall(pattern, response, re.IGNORECASE)
            files.extend(matches)
        return list(set(files))

    def _extract_commands(self, response: str) -> List[str]:
        """Extract suggested commands from Claude's response."""
        commands = []
        # Look for code blocks with shell commands
        code_blocks = re.findall(r"```(?:bash|sh|shell)?\n(.*?)```", response, re.DOTALL)
        for block in code_blocks:
            lines = block.strip().split("\n")
            for line in lines:
                line = line.strip()
                if line and not line.startswith("#"):
                    commands.append(line)
        return commands[:10]  # Limit to 10 suggestions
