from sqlalchemy import String, DateTime, ForeignKey, Enum, Text, JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship
from datetime import datetime
from typing import Optional
import enum
import uuid

from .base import Base


class JobType(str, enum.Enum):
    BUILD_APK = "build_apk"
    BUILD_WEB = "build_web"
    DEV_SERVER = "dev_server"
    TEST = "test"
    CUSTOM_COMMAND = "custom_command"


class JobStatus(str, enum.Enum):
    QUEUED = "queued"
    RUNNING = "running"
    SUCCESS = "success"
    FAILED = "failed"
    CANCELLED = "cancelled"


class Job(Base):
    __tablename__ = "jobs"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid.uuid4())
    )
    project_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("projects.id"), index=True
    )
    owner_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("users.id"), index=True
    )
    type: Mapped[JobType] = mapped_column(Enum(JobType))
    status: Mapped[JobStatus] = mapped_column(
        Enum(JobStatus), default=JobStatus.QUEUED
    )
    command: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    log_path: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow
    )
    started_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime, nullable=True
    )
    finished_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime, nullable=True
    )
    metadata_json: Mapped[Optional[dict]] = mapped_column(
        JSON, nullable=True, default=dict
    )
    # Process ID for running jobs (useful for dev_server to stop it)
    pid: Mapped[Optional[int]] = mapped_column(nullable=True)

    # Relationships
    project: Mapped["Project"] = relationship("Project", back_populates="jobs")
    owner: Mapped["User"] = relationship("User", back_populates="jobs")
