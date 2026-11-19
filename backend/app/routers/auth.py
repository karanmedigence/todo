
from collections.abc import Callable
from uuid import UUID

import jwt
from bson import ObjectId
from bson.errors import InvalidId
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pymongo.errors import DuplicateKeyError
from pwdlib import PasswordHash

from app.db.connection import users_collection
from app.schemas.user import (
    AuthTokenResponse,
    CurrentUserResponse,
    DeviceListResponse,
    DeviceLoginRequest,
    DeviceResponse,
    LogoutAllResponse,
    LogoutResponse,
    LogoutRequest,
    RefreshTokenRequest,
    TokenPairResponse,
    UserLogin,
    UserRegister,
    UserResponse,
)
from app.services.token_service import (
    InvalidDeviceCredentials,
    InvalidRefreshToken,
    RevokedDevice,
    authenticate_device,
    issue_token_pair,
    is_device_credential_active,
    list_device_credentials,
    register_device_credential,
    revoke_all_sessions,
    revoke_device_credential,
    revoke_refresh_session,
    rotate_refresh_token,
    token_expiration_seconds,
)
from app.utils.security import decode_access_token_claims

router = APIRouter(
    prefix="/auth",
    tags=["Authentication"]
)

password_hash = PasswordHash.recommended()
bearer_scheme = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> dict[str, str]:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        claims = decode_access_token_claims(credentials.credentials)
        user_id = claims["sub"]
        user_object_id = ObjectId(user_id)
    except (jwt.InvalidTokenError, ValueError, InvalidId):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"}
        )

    user = users_collection.find_one({"_id": user_object_id})
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"}
        )

    device_id = claims.get("did")
    if device_id is not None and not is_device_credential_active(user_id, device_id):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

    role = user.get("role", "user")
    if role not in {"user", "admin"}:
        role = "user"

    return {
        "id": str(user["_id"]),
        "name": user["name"],
        "email": user["email"],
        "role": role,
    }


def require_role(*allowed_roles: str) -> Callable[..., dict[str, str]]:
    if not allowed_roles:
        raise ValueError("At least one role must be specified")

    def check_role(
        current_user: dict[str, str] = Depends(get_current_user),
    ) -> dict[str, str]:
        if current_user.get("role") not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Insufficient permissions",
            )
        return current_user

    return check_role


@router.post(
    "/register",
    response_model=UserResponse,
    status_code=status.HTTP_201_CREATED
)
def register_user(user: UserRegister):

    # Check if email already exists
    existing_user = users_collection.find_one(
        {"email": user.email}
    )

    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered"
        )

    # Hash password
    hashed_password = password_hash.hash(user.password)

    # Create user document
    user_data = {
        "name": user.name,
        "email": user.email,
        "password": hashed_password,
        "role": "user",
    }

    try:
        result = users_collection.insert_one(user_data)

    except DuplicateKeyError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered"
        )

    return {
        "id": str(result.inserted_id),
        "name": user.name,
        "email": user.email,
        "role": "user",
        "message": "User registered successfully"
    }


@router.post(
    "/login",
    response_model=AuthTokenResponse,
    status_code=status.HTTP_200_OK
)
def login_user(user: UserLogin):

    # Check if email already exists
    existing_user = users_collection.find_one(
        {"email": user.email}
    )

    if not existing_user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    password_matches = password_hash.verify(
        user.password,
        existing_user["password"]
    )

    if not password_matches:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials"
        )

    device_id = str(user.device_id) if user.device_id is not None else None
    if device_id is not None and user.device_secret is not None:
        try:
            register_device_credential(
                user_id=str(existing_user["_id"]),
                device_id=device_id,
                device_secret=user.device_secret,
                device_name=user.device_name.strip() if user.device_name else None,
            )
        except InvalidDeviceCredentials:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid device credentials",
            )

    token_pair = issue_token_pair(
        str(existing_user["_id"]),
        user.device_name.strip() if user.device_name else None,
        device_id=device_id,
    )
    access_expires_in, refresh_expires_in = token_expiration_seconds()
    return {
        "access_token": token_pair.access_token,
        "refresh_token": token_pair.refresh_token,
        "token_type": "bearer",
        "expires_in": access_expires_in,
        "refresh_expires_in": refresh_expires_in,
        "id": str(existing_user["_id"]),
        "name": existing_user["name"],
        "email": existing_user["email"],
        "role": existing_user.get("role", "user"),
        "message": "User logged in successfully"
    }


@router.post(
    "/device-login",
    response_model=AuthTokenResponse,
)
def device_login(request: DeviceLoginRequest) -> AuthTokenResponse:
    device_id = str(request.device_id)
    try:
        user = authenticate_device(
            user_id=request.user_id,
            device_id=device_id,
            device_secret=request.device_secret,
        )
    except InvalidDeviceCredentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid device credentials",
        )
    except RevokedDevice:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Device has been revoked",
        )

    token_pair = issue_token_pair(
        str(user["_id"]),
        user.get("device_name"),
        device_id=device_id,
    )
    access_expires_in, refresh_expires_in = token_expiration_seconds()
    return AuthTokenResponse(
        access_token=token_pair.access_token,
        refresh_token=token_pair.refresh_token,
        token_type="bearer",
        expires_in=access_expires_in,
        refresh_expires_in=refresh_expires_in,
        id=str(user["_id"]),
        name=user["name"],
        email=user["email"],
        role=user.get("role", "user"),
        message="Device login successful",
    )


@router.post("/refresh", response_model=TokenPairResponse)
def refresh_tokens(request: RefreshTokenRequest) -> TokenPairResponse:
    try:
        token_pair = rotate_refresh_token(request.refresh_token)
    except InvalidRefreshToken:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )

    access_expires_in, refresh_expires_in = token_expiration_seconds()
    return TokenPairResponse(
        access_token=token_pair.access_token,
        refresh_token=token_pair.refresh_token,
        token_type="bearer",
        expires_in=access_expires_in,
        refresh_expires_in=refresh_expires_in,
    )


@router.post("/logout", response_model=LogoutResponse)
def logout(request: LogoutRequest) -> LogoutResponse:
    revoke_refresh_session(request.refresh_token)
    return LogoutResponse(message="Logged out")


@router.post("/logout-all", response_model=LogoutAllResponse)
def logout_all(
    current_user: dict[str, str] = Depends(get_current_user),
) -> LogoutAllResponse:
    revoked_sessions = revoke_all_sessions(current_user["id"])
    return LogoutAllResponse(
        message="Logged out from all devices",
        revoked_sessions=revoked_sessions,
    )


@router.get("/devices", response_model=DeviceListResponse)
def get_devices(
    # After lunch
    current_user: dict[str, str] = Depends(get_current_user),
) -> DeviceListResponse:
    devices = list_device_credentials(current_user["id"])
    return DeviceListResponse(
        devices=[
            DeviceResponse(
                device_id=device["device_id"],
                device_name=device.get("device_name"),
                created_at=device["created_at"],
                last_used_at=device.get("last_used_at"),
                is_revoked=device.get("is_revoked", False),
            )
            for device in devices
        ]
    )


@router.delete("/devices/{device_id}", response_model=LogoutResponse)
def revoke_device(
    device_id: UUID,
    current_user: dict[str, str] = Depends(get_current_user),
) -> LogoutResponse:
    if not revoke_device_credential(current_user["id"], str(device_id)):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Device not found",
        )
    return LogoutResponse(message="Device revoked")


@router.get("/me", response_model=CurrentUserResponse)
def get_me(
    current_user: dict[str, str] = Depends(get_current_user),
) -> CurrentUserResponse:
    return CurrentUserResponse(**current_user)
