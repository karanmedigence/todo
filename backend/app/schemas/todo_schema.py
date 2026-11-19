from pydantic import BaseModel, Field, field_validator
from typing import Optional


class TodoCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=100)
    description: Optional[str] = None


class TodoUpdate(BaseModel):
    title: Optional[str] = Field(default=None, min_length=1, max_length=100)
    description: Optional[str] = None
    is_completed: Optional[bool] = None

    @field_validator("title")
    @classmethod
    def title_cannot_be_null(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            raise ValueError("title cannot be null")
        return value


class TodoResponse(BaseModel):
    id: str
    title: str
    description: Optional[str] = None
    is_completed: bool