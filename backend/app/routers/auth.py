from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import timedelta

from ..database import get_db
from ..models import User, ClaudeSettings
from ..schemas import UserCreate, UserLogin, UserResponse, Token
from ..services.auth import AuthService, get_current_user
from ..services.workspace import WorkspaceService
from ..config import get_settings

router = APIRouter(prefix="/auth", tags=["auth"])
settings = get_settings()


@router.post("/register", response_model=Token)
async def register(
    user_data: UserCreate,
    db: AsyncSession = Depends(get_db)
):
    """Register a new user."""
    # Check if email already exists
    result = await db.execute(
        select(User).where(User.email == user_data.email)
    )
    if result.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered"
        )

    # Create user
    user = User(
        email=user_data.email,
        password_hash=AuthService.hash_password(user_data.password),
        display_name=user_data.display_name,
    )
    db.add(user)
    await db.flush()  # Get the user ID

    # Create default Claude settings
    claude_settings = ClaudeSettings(
        user_id=user.id,
        default_model=settings.default_model,
    )
    db.add(claude_settings)

    # Create workspace directories
    await WorkspaceService.create_user_workspace(user.id)

    # Sync Claude settings to disk
    await WorkspaceService.sync_claude_settings_to_disk(user.id, claude_settings)

    await db.commit()
    await db.refresh(user)

    # Create access token
    access_token = AuthService.create_access_token(
        data={"sub": user.id},
        expires_delta=timedelta(minutes=settings.access_token_expire_minutes)
    )

    return Token(
        access_token=access_token,
        user=UserResponse.model_validate(user)
    )


@router.post("/login", response_model=Token)
async def login(
    credentials: UserLogin,
    db: AsyncSession = Depends(get_db)
):
    """Login and get access token."""
    result = await db.execute(
        select(User).where(User.email == credentials.email)
    )
    user = result.scalar_one_or_none()

    if not user or not AuthService.verify_password(
        credentials.password, user.password_hash
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password"
        )

    access_token = AuthService.create_access_token(
        data={"sub": user.id},
        expires_delta=timedelta(minutes=settings.access_token_expire_minutes)
    )

    return Token(
        access_token=access_token,
        user=UserResponse.model_validate(user)
    )


@router.get("/me", response_model=UserResponse)
async def get_current_user_info(
    current_user: User = Depends(get_current_user)
):
    """Get current user info."""
    return UserResponse.model_validate(current_user)
