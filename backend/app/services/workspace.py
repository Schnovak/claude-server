import os
import shutil
import yaml
from pathlib import Path
from typing import Optional

from ..config import get_settings
from ..models import User, ClaudeSettings

settings = get_settings()


class WorkspaceService:
    """Service for managing user workspaces and Claude configurations."""

    @staticmethod
    async def create_user_workspace(user_id: str) -> Path:
        """Create workspace directories for a new user."""
        workspace = settings.get_user_workspace(user_id)
        projects_dir = settings.get_user_projects_path(user_id)
        claude_config = settings.get_user_claude_config_path(user_id)
        artifacts_dir = settings.get_user_artifacts_path(user_id)
        tmp_dir = settings.users_path / user_id / "tmp"

        # Create all directories
        for dir_path in [workspace, projects_dir, claude_config, artifacts_dir, tmp_dir]:
            dir_path.mkdir(parents=True, exist_ok=True)

        return workspace

    @staticmethod
    async def delete_user_workspace(user_id: str) -> None:
        """Delete a user's entire workspace (dangerous!)."""
        user_dir = settings.users_path / user_id
        if user_dir.exists():
            shutil.rmtree(user_dir)

        # Also delete artifacts
        artifacts_dir = settings.get_user_artifacts_path(user_id)
        if artifacts_dir.exists():
            shutil.rmtree(artifacts_dir)

    @staticmethod
    async def create_project_directory(user_id: str, project_id: str) -> Path:
        """Create a project directory within user's workspace."""
        project_path = settings.get_project_path(user_id, project_id)
        project_path.mkdir(parents=True, exist_ok=True)
        return project_path

    @staticmethod
    async def delete_project_directory(user_id: str, project_id: str) -> None:
        """Delete a project directory."""
        project_path = settings.get_project_path(user_id, project_id)
        if project_path.exists():
            shutil.rmtree(project_path)

    @staticmethod
    async def sync_claude_settings_to_disk(
        user_id: str,
        claude_settings: ClaudeSettings
    ) -> None:
        """Write Claude settings to the user's .claude directory."""
        claude_config_dir = settings.get_user_claude_config_path(user_id)
        claude_config_dir.mkdir(parents=True, exist_ok=True)

        settings_file = claude_config_dir / "settings.yaml"

        config_data = {
            "model": claude_settings.default_model,
        }

        if claude_settings.system_prompt:
            config_data["system_prompt"] = claude_settings.system_prompt

        if claude_settings.extra_instructions:
            config_data["extra_instructions"] = claude_settings.extra_instructions

        config_data["multi_project_workspace"] = claude_settings.use_workspace_multi_project

        with open(settings_file, "w") as f:
            yaml.dump(config_data, f, default_flow_style=False)

    @staticmethod
    async def read_claude_settings_from_disk(user_id: str) -> Optional[dict]:
        """Read Claude settings from the user's .claude directory."""
        settings_file = settings.get_user_claude_config_path(user_id) / "settings.yaml"

        if not settings_file.exists():
            return None

        with open(settings_file, "r") as f:
            return yaml.safe_load(f)

    @staticmethod
    def validate_path_within_workspace(user_id: str, path: Path) -> bool:
        """
        Security check: ensure a path is within the user's workspace.
        Returns True if path is safe, False otherwise.
        """
        workspace = settings.get_user_workspace(user_id)
        try:
            # Resolve to absolute path and check if it's under workspace
            resolved = path.resolve()
            return str(resolved).startswith(str(workspace.resolve()))
        except (ValueError, OSError):
            return False

    @staticmethod
    def get_relative_project_path(user_id: str, project_id: str) -> str:
        """Get project path relative to workspace root."""
        return f"projects/{project_id}"

    @staticmethod
    async def save_api_key(user_id: str, api_key: str) -> None:
        """Save the Anthropic API key for a user."""
        claude_config_dir = settings.get_user_claude_config_path(user_id)
        claude_config_dir.mkdir(parents=True, exist_ok=True)

        credentials_file = claude_config_dir / "credentials"
        with open(credentials_file, "w") as f:
            f.write(api_key)

        # Set restrictive permissions
        os.chmod(credentials_file, 0o600)

    @staticmethod
    async def get_api_key(user_id: str) -> Optional[str]:
        """Get the Anthropic API key for a user."""
        credentials_file = settings.get_user_claude_config_path(user_id) / "credentials"
        if not credentials_file.exists():
            return None

        with open(credentials_file, "r") as f:
            return f.read().strip()

    @staticmethod
    async def has_api_key(user_id: str) -> bool:
        """Check if a user has an API key configured."""
        credentials_file = settings.get_user_claude_config_path(user_id) / "credentials"
        return credentials_file.exists()
