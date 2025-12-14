from sqlalchemy import String, DateTime, Enum, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship
from datetime import datetime
from typing import Optional
import enum
import uuid

from .base import Base


class UserRole(str, enum.Enum):
    USER = "user"
    ADMIN = "admin"


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid.uuid4())
    )
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    display_name: Mapped[str] = mapped_column(String(100))
    role: Mapped[UserRole] = mapped_column(
        Enum(UserRole), default=UserRole.USER
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow
    )

    # Unix user for OS-level isolation
    unix_username: Mapped[Optional[str]] = mapped_column(
        String(32), unique=True, nullable=True
    )
    unix_uid: Mapped[Optional[int]] = mapped_column(
        Integer, unique=True, nullable=True
    )
    unix_gid: Mapped[Optional[int]] = mapped_column(
        Integer, nullable=True
    )

    # Relationships
    projects: Mapped[list["Project"]] = relationship(
        "Project", back_populates="owner", cascade="all, delete-orphan"
    )
    jobs: Mapped[list["Job"]] = relationship(
        "Job", back_populates="owner", cascade="all, delete-orphan"
    )
    artifacts: Mapped[list["Artifact"]] = relationship(
        "Artifact", back_populates="owner", cascade="all, delete-orphan"
    )
    claude_settings: Mapped["ClaudeSettings"] = relationship(
        "ClaudeSettings", back_populates="user", uselist=False,
        cascade="all, delete-orphan"
    )
    conversations: Mapped[list["Conversation"]] = relationship(
        "Conversation", back_populates="owner", cascade="all, delete-orphan"
    )
