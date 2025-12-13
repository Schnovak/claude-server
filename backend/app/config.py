from pydantic_settings import BaseSettings
from functools import lru_cache
from pathlib import Path

# Get the project root (parent of backend/)
PROJECT_ROOT = Path(__file__).parent.parent.parent.resolve()


class Settings(BaseSettings):
    # Server
    host: str = "0.0.0.0"
    port: int = 8000
    debug: bool = True

    # Database - relative to project root
    database_url: str = f"sqlite+aiosqlite:///{PROJECT_ROOT}/data/dev_platform.db"

    # JWT
    secret_key: str = "change-me-in-production"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 1440  # 24 hours

    # Paths - default to project directory structure
    base_path: Path = PROJECT_ROOT
    users_path: Path = PROJECT_ROOT / "users"
    data_path: Path = PROJECT_ROOT / "data"
    logs_path: Path = PROJECT_ROOT / "data" / "logs"

    # Claude
    claude_binary: str = "claude"
    default_model: str = "claude-sonnet-4-20250514"

    # Security
    require_sandbox: bool = True  # Fail if no sandbox available

    class Config:
        env_file = str(PROJECT_ROOT / "config" / ".env")
        env_file_encoding = "utf-8"

    @property
    def artifacts_path(self) -> Path:
        return self.data_path / "artifacts"

    @property
    def job_logs_path(self) -> Path:
        return self.logs_path / "jobs"

    def get_user_workspace(self, user_id: str) -> Path:
        """Get the workspace root for a user."""
        return self.users_path / user_id / "workspace"

    def get_user_projects_path(self, user_id: str) -> Path:
        """Get the projects directory for a user."""
        return self.get_user_workspace(user_id) / "projects"

    def get_user_claude_config_path(self, user_id: str) -> Path:
        """Get the .claude config directory for a user."""
        return self.get_user_workspace(user_id) / ".claude"

    def get_project_path(self, user_id: str, project_id: str) -> Path:
        """Get the path for a specific project."""
        return self.get_user_projects_path(user_id) / project_id

    def get_user_artifacts_path(self, user_id: str) -> Path:
        """Get the artifacts directory for a user."""
        return self.artifacts_path / user_id


@lru_cache()
def get_settings() -> Settings:
    return Settings()
