"""
Conversations router for per-project chat history persistence.
"""
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..database import get_db
from ..models import User, Project, Conversation, ConversationMessage
from ..schemas import (
    ConversationCreate,
    ConversationUpdate,
    ConversationResponse,
    ConversationWithMessagesResponse,
    ConversationMessageCreate,
    ConversationMessageResponse,
)
from ..services.auth import get_current_user

router = APIRouter(prefix="/projects/{project_id}/conversations", tags=["conversations"])


async def get_project_or_404(
    project_id: str,
    current_user: User,
    db: AsyncSession
) -> Project:
    """Get a project or raise 404."""
    result = await db.execute(
        select(Project).where(
            Project.id == project_id,
            Project.owner_id == current_user.id
        )
    )
    project = result.scalar_one_or_none()
    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found"
        )
    return project


async def get_conversation_or_404(
    conversation_id: str,
    project_id: str,
    current_user: User,
    db: AsyncSession
) -> Conversation:
    """Get a conversation or raise 404."""
    result = await db.execute(
        select(Conversation).where(
            Conversation.id == conversation_id,
            Conversation.project_id == project_id,
            Conversation.owner_id == current_user.id
        )
    )
    conversation = result.scalar_one_or_none()
    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found"
        )
    return conversation


@router.get("", response_model=List[ConversationResponse])
async def list_conversations(
    project_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """List all conversations for a project."""
    # Verify project access
    await get_project_or_404(project_id, current_user, db)

    # Get conversations with message count
    result = await db.execute(
        select(
            Conversation,
            func.count(ConversationMessage.id).label("message_count")
        )
        .outerjoin(ConversationMessage)
        .where(
            Conversation.project_id == project_id,
            Conversation.owner_id == current_user.id
        )
        .group_by(Conversation.id)
        .order_by(Conversation.updated_at.desc())
    )
    rows = result.all()

    conversations = []
    for conv, count in rows:
        response = ConversationResponse.model_validate(conv)
        response.message_count = count
        conversations.append(response)

    return conversations


@router.post("", response_model=ConversationResponse, status_code=status.HTTP_201_CREATED)
async def create_conversation(
    project_id: str,
    data: ConversationCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Create a new conversation for a project."""
    # Verify project access
    await get_project_or_404(project_id, current_user, db)

    now = datetime.utcnow()
    conversation = Conversation(
        project_id=project_id,
        owner_id=current_user.id,
        title=data.title,
        created_at=now,
        updated_at=now,
    )

    db.add(conversation)
    await db.commit()
    await db.refresh(conversation)

    response = ConversationResponse.model_validate(conversation)
    response.message_count = 0
    return response


@router.get("/{conversation_id}", response_model=ConversationWithMessagesResponse)
async def get_conversation(
    project_id: str,
    conversation_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get a conversation with all its messages."""
    # Verify project access
    await get_project_or_404(project_id, current_user, db)

    # Get conversation with messages
    result = await db.execute(
        select(Conversation)
        .options(selectinload(Conversation.messages))
        .where(
            Conversation.id == conversation_id,
            Conversation.project_id == project_id,
            Conversation.owner_id == current_user.id
        )
    )
    conversation = result.scalar_one_or_none()

    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found"
        )

    return ConversationWithMessagesResponse.model_validate(conversation)


@router.patch("/{conversation_id}", response_model=ConversationResponse)
async def update_conversation(
    project_id: str,
    conversation_id: str,
    data: ConversationUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Update a conversation's title."""
    # Verify project access
    await get_project_or_404(project_id, current_user, db)

    conversation = await get_conversation_or_404(
        conversation_id, project_id, current_user, db
    )

    if data.title is not None:
        conversation.title = data.title
        conversation.updated_at = datetime.utcnow()

    await db.commit()
    await db.refresh(conversation)

    # Get message count
    result = await db.execute(
        select(func.count(ConversationMessage.id))
        .where(ConversationMessage.conversation_id == conversation_id)
    )
    count = result.scalar() or 0

    response = ConversationResponse.model_validate(conversation)
    response.message_count = count
    return response


@router.delete("/{conversation_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_conversation(
    project_id: str,
    conversation_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Delete a conversation and all its messages."""
    # Verify project access
    await get_project_or_404(project_id, current_user, db)

    conversation = await get_conversation_or_404(
        conversation_id, project_id, current_user, db
    )

    await db.delete(conversation)
    await db.commit()


@router.post(
    "/{conversation_id}/messages",
    response_model=ConversationMessageResponse,
    status_code=status.HTTP_201_CREATED
)
async def add_message(
    project_id: str,
    conversation_id: str,
    data: ConversationMessageCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Add a message to a conversation."""
    # Verify project access
    await get_project_or_404(project_id, current_user, db)

    conversation = await get_conversation_or_404(
        conversation_id, project_id, current_user, db
    )

    now = datetime.utcnow()

    # Create message
    message = ConversationMessage(
        conversation_id=conversation_id,
        role=data.role,
        content=data.content,
        files_modified=data.files_modified,
        suggested_commands=data.suggested_commands,
        tokens_used=data.tokens_used,
        created_at=now,
    )

    db.add(message)

    # Update conversation timestamp and auto-generate title from first user message
    conversation.updated_at = now
    if not conversation.title and data.role.value == "user":
        # Use first 50 chars of first user message as title
        conversation.title = data.content[:50] + ("..." if len(data.content) > 50 else "")

    await db.commit()
    await db.refresh(message)

    return ConversationMessageResponse.model_validate(message)


@router.get(
    "/{conversation_id}/messages",
    response_model=List[ConversationMessageResponse]
)
async def list_messages(
    project_id: str,
    conversation_id: str,
    limit: int = 100,
    offset: int = 0,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """List messages in a conversation with pagination."""
    # Verify project access
    await get_project_or_404(project_id, current_user, db)

    # Verify conversation access
    await get_conversation_or_404(conversation_id, project_id, current_user, db)

    result = await db.execute(
        select(ConversationMessage)
        .where(ConversationMessage.conversation_id == conversation_id)
        .order_by(ConversationMessage.created_at.asc())
        .offset(offset)
        .limit(limit)
    )
    messages = result.scalars().all()

    return [ConversationMessageResponse.model_validate(m) for m in messages]
