from datetime import datetime, timezone
from typing import Literal

from pydantic import BaseModel, EmailStr, Field, field_validator


class ChatUserResponse(BaseModel):
    id: str
    name: str
    email: EmailStr


class ChatMessageResponse(BaseModel):
    id: str
    sender_id: str
    recipient_id: str
    content: str
    created_at: datetime

    @field_validator("created_at")
    @classmethod
    def normalize_created_at(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)


class ChatSocketAuth(BaseModel):
    type: Literal["authenticate"]
    token: str = Field(min_length=1)


class ChatSocketMessage(BaseModel):
    type: Literal["message"]
    content: str = Field(min_length=1, max_length=4000)

    @field_validator("content", mode="before")
    @classmethod
    def strip_content(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value
