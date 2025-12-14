from sqlalchemy import String, DateTime, ForeignKey, Enum
from sqlalchemy.orm import Mapped, mapped_column, relationship
from datetime import datetime
from typing import Optional
import enum
import uuid

from .base import Base


class ArtifactKind(str, enum.Enum):
    APK = "apk"
    AAB = "aab"  # Android App Bundle
    IPA = "ipa"
    ZIP = "zip"
    WEB_BUILD = "web_build"
    OTHER = "other"


class Artifact(Base):
    __tablename__ = "artifacts"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid.uuid4())
    )
    project_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("projects.id"), index=True
    )
    owner_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("users.id"), index=True
    )
    job_id: Mapped[Optional[str]] = mapped_column(
        String(36), ForeignKey("jobs.id"), nullable=True, index=True
    )
    file_path: Mapped[str] = mapped_column(String(500))
    kind: Mapped[ArtifactKind] = mapped_column(
        Enum(ArtifactKind), default=ArtifactKind.OTHER
    )
    label: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    file_size: Mapped[Optional[int]] = mapped_column(nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow
    )

    # Relationships
    project: Mapped["Project"] = relationship(
        "Project", back_populates="artifacts"
    )
    owner: Mapped["User"] = relationship("User", back_populates="artifacts")
    job: Mapped[Optional["Job"]] = relationship("Job", back_populates="artifacts")
