from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List

from ..database import get_db
from ..models import User, Project, ClaudeSettings
from ..schemas.claude import (
    ClaudeSettingsResponse,
    ClaudeSettingsUpdate,
    ClaudeApiKeyUpdate,
    GitHubTokenUpdate,
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

    # Build response with has_github_token computed field
    return ClaudeSettingsResponse(
        user_id=claude_settings.user_id,
        default_model=claude_settings.default_model,
        system_prompt=claude_settings.system_prompt,
        extra_instructions=claude_settings.extra_instructions,
        use_workspace_multi_project=claude_settings.use_workspace_multi_project,
        has_github_token=bool(claude_settings.github_token),
        updated_at=claude_settings.updated_at,
    )


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
    if update_data.github_token is not None:
        claude_settings.github_token = update_data.github_token

    # Sync to disk
    await WorkspaceService.sync_claude_settings_to_disk(
        current_user.id, claude_settings
    )

    await db.commit()
    await db.refresh(claude_settings)

    return ClaudeSettingsResponse(
        user_id=claude_settings.user_id,
        default_model=claude_settings.default_model,
        system_prompt=claude_settings.system_prompt,
        extra_instructions=claude_settings.extra_instructions,
        use_workspace_multi_project=claude_settings.use_workspace_multi_project,
        has_github_token=bool(claude_settings.github_token),
        updated_at=claude_settings.updated_at,
    )


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


# ============== GitHub Token ==============

@router.post("/github-token")
async def set_github_token(
    data: GitHubTokenUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Set the GitHub Personal Access Token for the current user."""
    result = await db.execute(
        select(ClaudeSettings).where(ClaudeSettings.user_id == current_user.id)
    )
    claude_settings = result.scalar_one_or_none()

    if not claude_settings:
        claude_settings = ClaudeSettings(user_id=current_user.id)
        db.add(claude_settings)

    claude_settings.github_token = data.github_token
    await db.commit()

    return {"message": "GitHub token saved successfully"}


@router.delete("/github-token")
async def remove_github_token(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Remove the GitHub Personal Access Token for the current user."""
    result = await db.execute(
        select(ClaudeSettings).where(ClaudeSettings.user_id == current_user.id)
    )
    claude_settings = result.scalar_one_or_none()

    if claude_settings:
        claude_settings.github_token = None
        await db.commit()

    return {"message": "GitHub token removed"}


@router.get("/github-token/status")
async def get_github_token_status(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Check if GitHub token is configured."""
    result = await db.execute(
        select(ClaudeSettings).where(ClaudeSettings.user_id == current_user.id)
    )
    claude_settings = result.scalar_one_or_none()
    has_token = bool(claude_settings and claude_settings.github_token)
    return {"configured": has_token}


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


# ============== MCP CLI Integration ==============

@router.get("/mcp/status")
async def get_mcp_status(
    current_user: User = Depends(get_current_user),
):
    """Check if MCP CLI commands are supported."""
    service = ClaudeService(current_user.id)
    supported = await service.check_mcp_support()
    return {"supported": supported}


@router.get("/mcp/servers")
async def list_mcp_servers(
    current_user: User = Depends(get_current_user),
):
    """List installed MCP servers via CLI."""
    service = ClaudeService(current_user.id)
    servers = await service.list_mcp_servers_cli()
    return {"servers": servers}


@router.post("/mcp/servers")
async def add_mcp_server(
    name: str,
    command: str = None,
    scope: str = "user",
    current_user: User = Depends(get_current_user),
):
    """Add an MCP server via CLI."""
    service = ClaudeService(current_user.id)
    success = await service.add_mcp_server_cli(name, command, scope=scope)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to add MCP server"
        )
    return {"message": f"MCP server {name} added"}


@router.delete("/mcp/servers/{name}")
async def remove_mcp_server(
    name: str,
    scope: str = "user",
    current_user: User = Depends(get_current_user),
):
    """Remove an MCP server via CLI."""
    service = ClaudeService(current_user.id)
    success = await service.remove_mcp_server_cli(name, scope=scope)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="MCP server not found or removal failed"
        )
    return {"message": f"MCP server {name} removed"}


@router.get("/mcp/servers/{name}")
async def get_mcp_server(
    name: str,
    current_user: User = Depends(get_current_user),
):
    """Get info about a specific MCP server via CLI."""
    service = ClaudeService(current_user.id)
    info = await service.get_mcp_server_info_cli(name)
    if not info:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="MCP server not found"
        )
    return info


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
    # Fetch project details if specified
    project = None
    if request.project_id:
        result = await db.execute(
            select(Project).where(
                Project.id == request.project_id,
                Project.owner_id == current_user.id
            )
        )
        project = result.scalar_one_or_none()
        if not project:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Project not found"
            )

    service = ClaudeService(current_user.id)

    try:
        result = await service.send_message(
            message=request.message,
            project_id=request.project_id,
            project_name=project.name if project else None,
            project_type=project.type.value if project else None,
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


# ============== Streaming Chat ==============

@router.post("/message/stream")
async def send_message_stream(
    request: ClaudeMessageRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Send a message to Claude and stream the response using Server-Sent Events."""
    # Fetch project details if specified
    project = None
    if request.project_id:
        result = await db.execute(
            select(Project).where(
                Project.id == request.project_id,
                Project.owner_id == current_user.id
            )
        )
        project = result.scalar_one_or_none()
        if not project:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Project not found"
            )

    service = ClaudeService(current_user.id)

    async def event_generator():
        try:
            async for chunk in service.send_message_stream(
                message=request.message,
                project_id=request.project_id,
                project_name=project.name if project else None,
                project_type=project.type.value if project else None,
                continue_conversation=request.continue_conversation,
            ):
                # SSE format: data: <json>\n\n
                yield f"data: {chunk}\n\n"
        except Exception as e:
            import json
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",  # Disable nginx buffering
        }
    )
