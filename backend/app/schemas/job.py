from pydantic import BaseModel
from datetime import datetime
from typing import Optional
from enum import Enum


class JobType(str, Enum):
    BUILD_APK = "build_apk"
    BUILD_WEB = "build_web"
    DEV_SERVER = "dev_server"
    TEST = "test"
    CUSTOM_COMMAND = "custom_command"


class JobStatus(str, Enum):
    QUEUED = "queued"
    RUNNING = "running"
    SUCCESS = "success"
    FAILED = "failed"
    CANCELLED = "cancelled"


class JobCreate(BaseModel):
    type: JobType
    command: Optional[str] = None  # Only for custom_command type


class JobResponse(BaseModel):
    id: str
    project_id: str
    owner_id: str
    type: JobType
    status: JobStatus
    command: Optional[str] = None
    log_path: Optional[str] = None
    created_at: datetime
    started_at: Optional[datetime] = None
    finished_at: Optional[datetime] = None
    metadata_json: Optional[dict] = None

    class Config:
        from_attributes = True
