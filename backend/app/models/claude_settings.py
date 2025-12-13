from sqlalchemy import String, DateTime, ForeignKey, Text, Boolean
from sqlalchemy.orm import Mapped, mapped_column, relationship
from datetime import datetime
from typing import Optional

from .base import Base


class ClaudeSettings(Base):
    __tablename__ = "claude_settings"

    user_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("users.id"), primary_key=True
    )
    default_model: Mapped[str] = mapped_column(
        String(100), default="claude-sonnet-4-20250514"
    )
    system_prompt: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    extra_instructions: Mapped[Optional[str]] = mapped_column(
        Text, nullable=True
    )
    use_workspace_multi_project: Mapped[bool] = mapped_column(
        Boolean, default=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )

    # Relationships
    user: Mapped["User"] = relationship(
        "User", back_populates="claude_settings"
    )
