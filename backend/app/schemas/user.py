
from datetime import datetime
from typing import Literal, Self
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field, model_validator


class UserRegister(BaseModel):
    name: str = Field(min_length=2, max_length=50)
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class UserLogin(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    device_name: str | None = Field(default=None, max_length=100)
    device_id: UUID | None = None
    device_secret: str | None = Field(
        default=None,
        min_length=64,
        max_length=64,
        pattern=r"^[A-Za-z0-9_-]{64}$",
    )

    @model_validator(mode="after")
    def validate_device_credentials(self) -> Self:
        if (self.device_id is None) != (self.device_secret is None):
            raise ValueError("device_id and device_secret must be provided together")
        return self


class UserResponse(BaseModel):
    id: str
    name: str
    email: EmailStr
    role: Literal["user", "admin"]
    message: str


class AdminUserCreate(BaseModel):
    name: str = Field(min_length=2, max_length=50)
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    role: Literal["user", "admin"] = "user"


class AdminUserUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=50)
    email: EmailStr | None = None
    password: str | None = Field(default=None, min_length=8, max_length=128)
    role: Literal["user", "admin"] | None = None

    @model_validator(mode="after")
    def validate_updates(self) -> Self:
        updates = self.model_dump(exclude_unset=True)
        if not updates:
            raise ValueError("At least one user field must be provided")
        if any(value is None for value in updates.values()):
            raise ValueError("User fields cannot be null")
        return self


class AdminUserResponse(BaseModel):
    id: str
    name: str
    email: EmailStr
    role: Literal["user", "admin"]


class TokenPairResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: Literal["bearer"]
    expires_in: int
    refresh_expires_in: int


class AuthTokenResponse(TokenPairResponse):
    id: str
    name: str
    email: EmailStr
    role: Literal["user", "admin"]
    message: str


class RefreshTokenRequest(BaseModel):
    refresh_token: str = Field(min_length=1)


class DeviceLoginRequest(BaseModel):
    user_id: str = Field(min_length=24, max_length=24, pattern=r"^[0-9a-fA-F]{24}$")
    device_id: UUID
    device_secret: str = Field(
        min_length=64,
        max_length=64,
        pattern=r"^[A-Za-z0-9_-]{64}$",
    )


class LogoutRequest(BaseModel):
    refresh_token: str = Field(min_length=1)


class CurrentUserResponse(BaseModel):
    id: str
    name: str
    email: EmailStr
    role: Literal["user", "admin"]


class LogoutResponse(BaseModel):
    message: str


class LogoutAllResponse(BaseModel):
    message: str
    revoked_sessions: int


class DeviceResponse(BaseModel):
    device_id: str
    device_name: str | None
    created_at: datetime
    last_used_at: datetime | None
    is_revoked: bool


class DeviceListResponse(BaseModel):
    devices: list[DeviceResponse]
