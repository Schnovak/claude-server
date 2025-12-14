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

    def _build_system_prompt(
        self,
        project_name: Optional[str] = None,
        project_type: Optional[str] = None,
        project_path: Optional[Path] = None,
    ) -> str:
        """Build a comprehensive system prompt giving Claude full context."""

        project_context = ""
        if project_name:
            project_context = f"""
## Current Project
- **Name:** {project_name}
- **Type:** {project_type or 'general'}
- **Path:** {project_path or 'workspace root'}

You are working within this project's directory. All file operations are relative to this project unless an absolute path is specified.
"""

        type_specific_hints = ""
        if project_type:
            hints = {
                "flutter": """
### Flutter Project Guidelines
- Use `flutter pub get` to install dependencies
- Run `flutter analyze` to check for issues
- Use `flutter run` to test the app
- Edit files in `lib/` for Dart code
- The `pubspec.yaml` defines dependencies
""",
                "python": """
### Python Project Guidelines
- Check for `requirements.txt` or `pyproject.toml` for dependencies
- Use virtual environments when available
- Run tests with `pytest` if available
- Follow PEP 8 style guidelines
""",
                "node": """
### Node.js Project Guidelines
- Use `npm install` or `yarn` to install dependencies
- Check `package.json` for scripts and dependencies
- Use `npm run` to execute defined scripts
- Look for TypeScript config in `tsconfig.json`
""",
                "web": """
### Web Project Guidelines
- Check for framework-specific configs (webpack, vite, etc.)
- Look for `index.html` as entry point
- CSS/SCSS files for styling
- JavaScript/TypeScript for functionality
""",
            }
            type_specific_hints = hints.get(project_type.lower(), "")

        return f"""# Claude Server Assistant

You are Claude, an AI assistant integrated into Claude Server - a web-based development platform. You help users build, edit, and manage software projects directly through this interface.

## Platform Overview
Claude Server is a self-hosted development environment that allows users to:
- Create and manage multiple projects
- Chat with you (Claude) to get coding help
- Browse and edit files in their projects
- Manage Git repositories and push to GitHub
- All within a web browser interface

## Your Capabilities
You have full access to the project's file system and can:

### File Operations
- **Read files:** View any file in the project
- **Write files:** Create new files with content
- **Edit files:** Modify existing files precisely
- **Search:** Find files by name (glob) or content (grep)

### Terminal Operations
- **Run commands:** Execute bash commands in the project directory
- **Build/compile:** Run build tools, compilers, test suites
- **Git operations:** Stage, commit, and manage version control

### Code Assistance
- Explain code and architecture
- Debug issues and fix bugs
- Implement new features
- Refactor and improve code quality
- Write tests and documentation
{project_context}{type_specific_hints}
## Guidelines

1. **Be proactive:** When asked to implement something, do it directly. Don't just explain - write the code.

2. **Make complete changes:** When editing files, make all necessary changes. Don't leave TODOs or placeholders.

3. **Preserve working code:** Be careful not to break existing functionality. Test your understanding before making changes.

4. **Explain when helpful:** Briefly explain what you're doing, but focus on action over explanation.

5. **Use appropriate tools:** Choose the right tool for each task - Read for viewing, Edit for modifications, Bash for commands.

6. **Handle errors gracefully:** If something fails, explain what went wrong and try alternative approaches.

7. **Stay focused:** Work on what the user asks. Don't make unrequested changes or add unnecessary features.

8. **Security conscious:** Never expose secrets, API keys, or sensitive data. Don't run dangerous commands.

## Response Style
- Be concise and direct
- Show file paths when referencing code
- Use markdown formatting for readability
- When showing code changes, be specific about what changed and why
- Do NOT add notes, disclaimers, or summaries at the end of your responses
- Do NOT add "Note:" sections unless explicitly relevant to the task
- End responses naturally without extra commentary
- When starting a dev server or any localhost URL, ALWAYS output it as a clickable markdown link: [http://localhost:PORT](http://localhost:PORT)
"""

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
        project_name: Optional[str] = None,
        project_type: Optional[str] = None,
        continue_conversation: bool = False,
    ) -> Dict[str, Any]:
        """
        Send a message to Claude Code and get a response.

        Args:
            message: The message to send
            project_id: Optional project to focus on
            project_name: Name of the project for context
            project_type: Type of project (flutter, python, node, web, other)
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

        # Add system prompt with full context
        system_prompt = self._build_system_prompt(
            project_name=project_name,
            project_type=project_type,
            project_path=cwd,
        )
        cmd.extend(["--system-prompt", system_prompt])

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
        project_name: Optional[str] = None,
        project_type: Optional[str] = None,
        continue_conversation: bool = False,
    ) -> AsyncGenerator[str, None]:
        """
        Send a message to Claude Code and stream the response.

        Yields JSON strings with either 'text' chunks or final 'done' message.
        Uses --output-format stream-json for real-time streaming.
        """
        # Determine working directory
        if project_id:
            cwd = settings.get_project_path(self.user_id, project_id)
        else:
            cwd = self.workspace

        # Build command with streaming output format
        cmd = [settings.claude_binary]
        cmd.extend(["--print", "-p", message])
        cmd.extend(["--output-format", "stream-json"])
        cmd.append("--verbose")  # Required for stream-json
        cmd.append("--include-partial-messages")

        # Add system prompt with full context
        system_prompt = self._build_system_prompt(
            project_name=project_name,
            project_type=project_type,
            project_path=cwd,
        )
        cmd.extend(["--system-prompt", system_prompt])

        # Bypass permission prompts - safe because we sandbox with firejail
        cmd.extend(["--permission-mode", "bypassPermissions"])

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
            buffer = ""
            last_block_was_tool = False  # Track if last block was a tool use

            # Read stdout and parse stream-json events
            while True:
                try:
                    chunk = await asyncio.wait_for(
                        process.stdout.read(4096),
                        timeout=300
                    )
                    if not chunk:
                        break

                    buffer += chunk.decode("utf-8", errors="replace")

                    # Process complete JSON lines
                    while "\n" in buffer:
                        line, buffer = buffer.split("\n", 1)
                        line = line.strip()
                        if not line:
                            continue

                        try:
                            event = json.loads(line)
                            event_type = event.get("type", "")

                            # Handle stream_event (contains nested event with deltas)
                            if event_type == "stream_event":
                                inner_event = event.get("event", {})
                                inner_type = inner_event.get("type", "")

                                if inner_type == "content_block_start":
                                    content_block = inner_event.get("content_block", {})
                                    if content_block.get("type") == "tool_use":
                                        # Tool use starting - show what Claude is doing
                                        tool_name = content_block.get("name", "unknown")
                                        last_block_was_tool = True
                                        yield json.dumps({
                                            "activity": {
                                                "type": "tool_start",
                                                "tool": tool_name,
                                            }
                                        })
                                    elif content_block.get("type") == "text":
                                        # Text block starting - add newline if coming after tool
                                        if last_block_was_tool and full_response:
                                            full_response += "\n\n"
                                            yield json.dumps({"text": "\n\n"})
                                        last_block_was_tool = False

                                elif inner_type == "content_block_delta":
                                    delta = inner_event.get("delta", {})
                                    delta_type = delta.get("type", "")

                                    if delta_type == "text_delta":
                                        text = delta.get("text", "")
                                        if text:
                                            full_response += text
                                            yield json.dumps({"text": text})

                                    elif delta_type == "input_json_delta":
                                        # Tool input being built - can show partial tool args
                                        partial_json = delta.get("partial_json", "")
                                        if partial_json:
                                            yield json.dumps({
                                                "activity": {
                                                    "type": "tool_input",
                                                    "partial": partial_json,
                                                }
                                            })

                                elif inner_type == "content_block_stop":
                                    # Content block finished
                                    yield json.dumps({
                                        "activity": {
                                            "type": "tool_end",
                                        }
                                    })

                            elif event_type == "assistant":
                                # Assistant message - may contain tool use info
                                message = event.get("message", {})
                                content = message.get("content", [])
                                for block in content:
                                    if block.get("type") == "tool_use":
                                        tool_name = block.get("name", "")
                                        tool_input = block.get("input", {})
                                        yield json.dumps({
                                            "activity": {
                                                "type": "tool_call",
                                                "tool": tool_name,
                                                "input": tool_input,
                                            }
                                        })

                            elif event_type == "result":
                                # Final result - capture any remaining text
                                result_text = event.get("result", "")
                                if result_text and len(result_text) > len(full_response):
                                    new_text = result_text[len(full_response):]
                                    if new_text:
                                        yield json.dumps({"text": new_text})
                                    full_response = result_text

                        except json.JSONDecodeError:
                            # Not valid JSON, might be partial - skip
                            continue

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

    async def check_mcp_support(self) -> bool:
        """
        Check if 'claude mcp' commands are available.

        Returns:
            True if MCP commands are supported
        """
        try:
            process = await asyncio.create_subprocess_exec(
                settings.claude_binary, "mcp", "--help",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            await process.communicate()
            return process.returncode == 0
        except Exception:
            return False

    async def list_mcp_servers_cli(self) -> List[Dict[str, Any]]:
        """
        List installed MCP servers using 'claude mcp list'.

        Returns:
            List of MCP server dictionaries
        """
        try:
            env = {**os.environ, "CLAUDE_CONFIG_DIR": str(self.claude_config)}
            api_key = await self.get_api_key()
            if api_key:
                env["ANTHROPIC_API_KEY"] = api_key

            process = await asyncio.create_subprocess_exec(
                settings.claude_binary, "mcp", "list",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=env,
            )
            stdout, stderr = await process.communicate()

            if process.returncode != 0:
                logger.warning(f"mcp list failed: {stderr.decode()}")
                return []

            # Parse the output
            output = stdout.decode().strip()
            servers = []

            # The output format is typically a table or JSON
            # Try to parse as JSON first
            try:
                data = json.loads(output)
                if isinstance(data, list):
                    return data
                elif isinstance(data, dict):
                    for name, config in data.items():
                        servers.append({
                            "name": name,
                            "command": config.get("command", ""),
                            "args": config.get("args", []),
                            "enabled": not config.get("disabled", False),
                        })
                    return servers
            except json.JSONDecodeError:
                pass

            # Parse as text output (line-based)
            for line in output.split("\n"):
                line = line.strip()
                if not line or line.startswith("-") or line.startswith("="):
                    continue
                # Extract server name from line
                parts = line.split()
                if parts:
                    servers.append({
                        "name": parts[0],
                        "enabled": True,
                    })

            return servers

        except Exception as e:
            logger.error(f"Error listing MCP servers: {e}")
            return []

    async def add_mcp_server_cli(
        self,
        name: str,
        command: Optional[str] = None,
        args: Optional[List[str]] = None,
        scope: str = "user"
    ) -> bool:
        """
        Add an MCP server using 'claude mcp add'.

        Args:
            name: Server name
            command: Command to run the server (optional for well-known servers)
            args: Arguments for the command
            scope: Scope (user, project, local)

        Returns:
            True if successful
        """
        try:
            env = {**os.environ, "CLAUDE_CONFIG_DIR": str(self.claude_config)}
            api_key = await self.get_api_key()
            if api_key:
                env["ANTHROPIC_API_KEY"] = api_key

            cmd = [settings.claude_binary, "mcp", "add", "-s", scope, name]

            if command:
                cmd.append("--")
                cmd.append(command)
                if args:
                    cmd.extend(args)

            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=env,
            )
            stdout, stderr = await process.communicate()

            if process.returncode != 0:
                logger.warning(f"mcp add failed: {stderr.decode()}")
                return False

            logger.info(f"Added MCP server: {name}")
            return True

        except Exception as e:
            logger.error(f"Error adding MCP server: {e}")
            return False

    async def remove_mcp_server_cli(self, name: str, scope: str = "user") -> bool:
        """
        Remove an MCP server using 'claude mcp remove'.

        Args:
            name: Server name to remove
            scope: Scope (user, project, local)

        Returns:
            True if successful
        """
        try:
            env = {**os.environ, "CLAUDE_CONFIG_DIR": str(self.claude_config)}
            api_key = await self.get_api_key()
            if api_key:
                env["ANTHROPIC_API_KEY"] = api_key

            cmd = [settings.claude_binary, "mcp", "remove", "-s", scope, name]

            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=env,
            )
            stdout, stderr = await process.communicate()

            if process.returncode != 0:
                logger.warning(f"mcp remove failed: {stderr.decode()}")
                return False

            logger.info(f"Removed MCP server: {name}")
            return True

        except Exception as e:
            logger.error(f"Error removing MCP server: {e}")
            return False

    async def get_mcp_server_info_cli(self, name: str) -> Optional[Dict[str, Any]]:
        """
        Get info about a specific MCP server using 'claude mcp get'.

        Args:
            name: Server name

        Returns:
            Server info dictionary or None
        """
        try:
            env = {**os.environ, "CLAUDE_CONFIG_DIR": str(self.claude_config)}
            api_key = await self.get_api_key()
            if api_key:
                env["ANTHROPIC_API_KEY"] = api_key

            process = await asyncio.create_subprocess_exec(
                settings.claude_binary, "mcp", "get", name,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=env,
            )
            stdout, stderr = await process.communicate()

            if process.returncode != 0:
                return None

            output = stdout.decode().strip()
            try:
                return json.loads(output)
            except json.JSONDecodeError:
                return {"name": name, "raw_output": output}

        except Exception as e:
            logger.error(f"Error getting MCP server info: {e}")
            return None

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
