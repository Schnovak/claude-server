from pydantic import BaseModel
from datetime import datetime
from typing import Optional
from enum import Enum


class ArtifactKind(str, Enum):
    APK = "apk"
    AAB = "aab"
    IPA = "ipa"
    ZIP = "zip"
    WEB_BUILD = "web_build"
    OTHER = "other"


class ArtifactResponse(BaseModel):
    id: str
    project_id: str
    owner_id: str
    file_path: str
    kind: ArtifactKind
    label: Optional[str] = None
    file_size: Optional[int] = None
    created_at: datetime

    class Config:
        from_attributes = True
