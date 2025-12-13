from pydantic import BaseModel
from datetime import datetime
from typing import Optional, List


class ClaudeSettingsResponse(BaseModel):
    user_id: str
    default_model: str
    system_prompt: Optional[str] = None
    extra_instructions: Optional[str] = None
    use_workspace_multi_project: bool = True
    has_github_token: bool = False  # Don't expose actual token
    updated_at: datetime

    class Config:
        from_attributes = True


class ClaudeSettingsUpdate(BaseModel):
    default_model: Optional[str] = None
    system_prompt: Optional[str] = None
    extra_instructions: Optional[str] = None
    use_workspace_multi_project: Optional[bool] = None
    api_key: Optional[str] = None
    github_token: Optional[str] = None


class ClaudeApiKeyUpdate(BaseModel):
    api_key: str


class GitHubTokenUpdate(BaseModel):
    github_token: str


class ClaudeMessageRequest(BaseModel):
    message: str
    project_id: Optional[str] = None  # If provided, focuses on this project
    continue_conversation: bool = False  # Continue previous conversation


class ClaudeMessageResponse(BaseModel):
    response: str
    conversation_id: Optional[str] = None
    files_modified: List[str] = []
    suggested_commands: List[str] = []


class ClaudePluginInfo(BaseModel):
    name: str
    version: Optional[str] = None
    description: Optional[str] = None
    enabled: bool = True
    installed: bool = False


class ClaudePluginInstall(BaseModel):
    name: str


class ClaudePluginToggle(BaseModel):
    name: str
    enabled: bool


class ClaudeCommandInfo(BaseModel):
    name: str
    description: Optional[str] = None
    usage: Optional[str] = None
