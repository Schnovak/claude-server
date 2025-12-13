from pydantic import BaseModel
from datetime import datetime
from typing import Optional
from enum import Enum


class ProjectType(str, Enum):
    FLUTTER = "flutter"
    WEB = "web"
    NODE = "node"
    PYTHON = "python"
    OTHER = "other"


class ProjectCreate(BaseModel):
    name: str
    type: ProjectType = ProjectType.OTHER


class ProjectResponse(BaseModel):
    id: str
    owner_id: str
    name: str
    type: ProjectType
    root_path: str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
