from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List

from ..database import get_db
from ..models import User, Project, ClaudeSettings
from ..schemas.claude import (
    ClaudeSettingsResponse,
    ClaudeSettingsUpdate,
    ClaudeApiKeyUpdate,
    ClaudeMessageRequest,
    ClaudeMessageResponse,
    ClaudePluginInfo,
    ClaudePluginInstall,
    ClaudePluginToggle,
    ClaudeCommandInfo,
)
from ..services.auth import get_current_user
from ..services.workspace import WorkspaceService
from ..services.claude_service import ClaudeService
from ..config import get_settings

router = APIRouter(prefix="/claude", tags=["claude"])
settings = get_settings()


# ============== Settings ==============

@router.get("/settings", response_model=ClaudeSettingsResponse)
async def get_claude_settings(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get Claude settings for current user."""
    result = await db.execute(
        select(ClaudeSettings).where(ClaudeSettings.user_id == current_user.id)
    )
    claude_settings = result.scalar_one_or_none()

    if not claude_settings:
        # Create default settings
        claude_settings = ClaudeSettings(
            user_id=current_user.id,
            default_model=settings.default_model,
        )
        db.add(claude_settings)
        await db.commit()
        await db.refresh(claude_settings)

    return ClaudeSettingsResponse.model_validate(claude_settings)


@router.post("/settings", response_model=ClaudeSettingsResponse)
async def update_claude_settings(
    update_data: ClaudeSettingsUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Update Claude settings for current user."""
    result = await db.execute(
        select(ClaudeSettings).where(ClaudeSettings.user_id == current_user.id)
    )
    claude_settings = result.scalar_one_or_none()

    if not claude_settings:
        claude_settings = ClaudeSettings(user_id=current_user.id)
        db.add(claude_settings)

    # Update fields
    if update_data.default_model is not None:
        claude_settings.default_model = update_data.default_model
    if update_data.system_prompt is not None:
        claude_settings.system_prompt = update_data.system_prompt
    if update_data.extra_instructions is not None:
        claude_settings.extra_instructions = update_data.extra_instructions
    if update_data.use_workspace_multi_project is not None:
        claude_settings.use_workspace_multi_project = update_data.use_workspace_multi_project

    # Sync to disk
    await WorkspaceService.sync_claude_settings_to_disk(
        current_user.id, claude_settings
    )

    await db.commit()
    await db.refresh(claude_settings)

    return ClaudeSettingsResponse.model_validate(claude_settings)


@router.get("/models", response_model=List[str])
async def get_available_models(
    current_user: User = Depends(get_current_user),
):
    """Get list of available Claude models."""
    service = ClaudeService(current_user.id)
    return await service.get_available_models()


@router.post("/api-key")
async def set_api_key(
    data: ClaudeApiKeyUpdate,
    current_user: User = Depends(get_current_user),
):
    """Set the Anthropic API key for the current user."""
    await WorkspaceService.save_api_key(current_user.id, data.api_key)
    return {"message": "API key saved successfully"}


@router.get("/api-key/status")
async def get_api_key_status(
    current_user: User = Depends(get_current_user),
):
    """Check if API key is configured."""
    has_key = await WorkspaceService.has_api_key(current_user.id)
    return {"configured": has_key}


# ============== Plugins ==============

@router.get("/plugins", response_model=List[ClaudePluginInfo])
async def list_plugins(
    current_user: User = Depends(get_current_user),
):
    """List installed plugins for current user."""
    service = ClaudeService(current_user.id)
    plugins = await service.list_plugins()
    return [ClaudePluginInfo(**p) for p in plugins]


@router.get("/plugins/search", response_model=List[ClaudePluginInfo])
async def search_plugins(
    query: str = "",
    current_user: User = Depends(get_current_user),
):
    """Search available plugins."""
    service = ClaudeService(current_user.id)
    plugins = await service.search_plugins(query)
    return [ClaudePluginInfo(
        name=p["name"],
        description=p.get("description"),
        installed=False,
    ) for p in plugins]


@router.post("/plugins/install")
async def install_plugin(
    plugin_data: ClaudePluginInstall,
    current_user: User = Depends(get_current_user),
):
    """Install a plugin."""
    service = ClaudeService(current_user.id)
    success = await service.install_plugin(plugin_data.name)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to install plugin"
        )
    return {"message": f"Plugin {plugin_data.name} installed"}


@router.post("/plugins/uninstall")
async def uninstall_plugin(
    plugin_data: ClaudePluginInstall,
    current_user: User = Depends(get_current_user),
):
    """Uninstall a plugin."""
    service = ClaudeService(current_user.id)
    success = await service.uninstall_plugin(plugin_data.name)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Plugin not found"
        )
    return {"message": f"Plugin {plugin_data.name} uninstalled"}


@router.post("/plugins/toggle")
async def toggle_plugin(
    toggle_data: ClaudePluginToggle,
    current_user: User = Depends(get_current_user),
):
    """Enable or disable a plugin."""
    service = ClaudeService(current_user.id)
    success = await service.toggle_plugin(toggle_data.name, toggle_data.enabled)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Plugin not found"
        )
    status_str = "enabled" if toggle_data.enabled else "disabled"
    return {"message": f"Plugin {toggle_data.name} {status_str}"}


# ============== Commands (Advanced) ==============

@router.get("/commands", response_model=List[ClaudeCommandInfo])
async def list_commands(
    current_user: User = Depends(get_current_user),
):
    """List available Claude commands."""
    # These are common Claude Code commands
    commands = [
        ClaudeCommandInfo(
            name="help",
            description="Show help for Claude Code",
            usage="claude --help"
        ),
        ClaudeCommandInfo(
            name="chat",
            description="Start an interactive chat session",
            usage="claude"
        ),
        ClaudeCommandInfo(
            name="print",
            description="Non-interactive mode, prints response",
            usage="claude --print -p 'your message'"
        ),
        ClaudeCommandInfo(
            name="continue",
            description="Continue previous conversation",
            usage="claude --continue"
        ),
    ]
    return commands


# ============== Chat/Message ==============

@router.post("/message", response_model=ClaudeMessageResponse)
async def send_message(
    request: ClaudeMessageRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Send a message to Claude and get a response."""
    # Verify project if specified
    if request.project_id:
        result = await db.execute(
            select(Project).where(
                Project.id == request.project_id,
                Project.owner_id == current_user.id
            )
        )
        if not result.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Project not found"
            )

    service = ClaudeService(current_user.id)

    try:
        result = await service.send_message(
            message=request.message,
            project_id=request.project_id,
            continue_conversation=request.continue_conversation,
        )

        return ClaudeMessageResponse(
            response=result["response"],
            files_modified=result.get("files_modified", []),
            suggested_commands=result.get("suggested_commands", []),
        )

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error communicating with Claude: {str(e)}"
        )


@router.post("/projects/{project_id}/claude/message", response_model=ClaudeMessageResponse)
async def send_project_message(
    project_id: str,
    request: ClaudeMessageRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Send a message to Claude in the context of a specific project."""
    # Override project_id from path
    request.project_id = project_id
    return await send_message(request, current_user, db)
