from pydantic import BaseModel, field_validator
from datetime import datetime
from typing import Optional, List, Any
from enum import Enum
import json


class MessageRole(str, Enum):
    USER = "user"
    ASSISTANT = "assistant"


class ConversationCreate(BaseModel):
    title: Optional[str] = None


class ConversationUpdate(BaseModel):
    title: Optional[str] = None


class ConversationMessageCreate(BaseModel):
    role: MessageRole
    content: str
    files_modified: Optional[List[str]] = None
    suggested_commands: Optional[List[str]] = None
    tokens_used: Optional[int] = None


class ConversationMessageResponse(BaseModel):
    id: str
    conversation_id: str
    role: MessageRole
    content: str
    files_modified: Optional[List[str]] = None
    suggested_commands: Optional[List[str]] = None
    tokens_used: Optional[int] = None
    created_at: datetime

    @field_validator('files_modified', 'suggested_commands', mode='before')
    @classmethod
    def parse_json_list(cls, v: Any) -> Optional[List[str]]:
        """Parse JSON string to list if needed."""
        if v is None:
            return None
        if isinstance(v, str):
            try:
                return json.loads(v)
            except json.JSONDecodeError:
                return None
        return v

    class Config:
        from_attributes = True


class ConversationResponse(BaseModel):
    id: str
    project_id: str
    owner_id: str
    title: Optional[str]
    created_at: datetime
    updated_at: datetime
    message_count: int = 0

    class Config:
        from_attributes = True


class ConversationWithMessagesResponse(BaseModel):
    id: str
    project_id: str
    owner_id: str
    title: Optional[str]
    created_at: datetime
    updated_at: datetime
    messages: List[ConversationMessageResponse]

    class Config:
        from_attributes = True
