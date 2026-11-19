import hashlib
import hmac
import secrets
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

import jwt
from bson import ObjectId
from bson.errors import InvalidId
from pymongo import ReturnDocument
from pymongo.errors import DuplicateKeyError

from app.db.connection import (
    device_credentials_collection,
    refresh_tokens_collection,
    users_collection,
)
from app.utils.security import (
    ACCESS_TOKEN_EXPIRE_SECONDS,
    REFRESH_TOKEN_EXPIRE_SECONDS,
    create_access_token,
    create_refresh_token,
    decode_refresh_token,
)


class InvalidRefreshToken(Exception):
    pass


class InvalidDeviceCredentials(Exception):
    pass


class RevokedDevice(Exception):
    pass


@dataclass(frozen=True)
class TokenPair:
    access_token: str
    refresh_token: str


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _device_secret_hash(secret: str) -> str:
    return hashlib.sha256(secret.encode("utf-8")).hexdigest()


def _session_filter(session_id: str) -> dict[str, Any]:
    return {"session_id": session_id, "revoked_at": None}


def _is_expired(expires_at: datetime | None, now: datetime) -> bool:
    if expires_at is None:
        return True
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    return expires_at <= now


def _revoke_session(session_id: str, now: datetime | None = None) -> None:
    refresh_tokens_collection.update_many(
        _session_filter(session_id),
        {
            "$set": {
                "revoked_at": now or datetime.now(timezone.utc),
                "is_active": False,
            }
        },
    )


def _require_user(user_id: str) -> None:
    try:
        user_object_id = ObjectId(user_id)
    except InvalidId as error:
        raise InvalidRefreshToken from error
    if users_collection.find_one({"_id": user_object_id}) is None:
        raise InvalidRefreshToken


def _insert_refresh_token(
    *,
    token: str,
    token_id: str,
    user_id: str,
    session_id: str,
    device_name: str | None,
    expires_at: datetime,
    created_at: datetime,
    is_active: bool,
    device_id: str | None = None,
) -> ObjectId:
    result = refresh_tokens_collection.insert_one(
        {
            "user_id": user_id,
            "session_id": session_id,
            "token_hash": _token_hash(token),
            "token_id": token_id,
            "device_name": device_name,
            "device_id": device_id,
            "created_at": created_at,
            "expires_at": expires_at,
            "revoked_at": None,
            "replaced_by": None,
            "is_active": is_active,
        }
    )
    return result.inserted_id


def register_device_credential(
    *,
    user_id: str,
    device_id: str,
    device_secret: str,
    device_name: str | None,
) -> None:
    now = datetime.now(timezone.utc)
    secret_hash = _device_secret_hash(device_secret)
    device_filter = {"user_id": user_id, "device_id": device_id}
    credential = device_credentials_collection.find_one(device_filter)

    if credential is None:
        try:
            device_credentials_collection.insert_one(
                {
                    **device_filter,
                    "device_secret_hash": secret_hash,
                    "device_name": device_name,
                    "created_at": now,
                    "last_used_at": now,
                    "is_revoked": False,
                    "revoked_at": None,
                }
            )
            return
        except DuplicateKeyError:
            credential = device_credentials_collection.find_one(device_filter)
            if credential is None:
                raise

    if not hmac.compare_digest(credential["device_secret_hash"], secret_hash):
        raise InvalidDeviceCredentials

    device_credentials_collection.update_one(
        {"_id": credential["_id"]},
        {
            "$set": {
                "device_name": device_name or credential.get("device_name"),
                "last_used_at": now,
                "is_revoked": False,
                "revoked_at": None,
            }
        },
    )


def authenticate_device(
    *,
    user_id: str,
    device_id: str,
    device_secret: str,
) -> dict[str, Any]:
    try:
        user_object_id = ObjectId(user_id)
    except InvalidId as error:
        raise InvalidDeviceCredentials from error

    credential = device_credentials_collection.find_one(
        {"user_id": user_id, "device_id": device_id}
    )
    if credential is None or not hmac.compare_digest(
        credential["device_secret_hash"],
        _device_secret_hash(device_secret),
    ):
        raise InvalidDeviceCredentials
    if credential.get("is_revoked") is True:
        raise RevokedDevice

    user = users_collection.find_one({"_id": user_object_id})
    if user is None:
        raise InvalidDeviceCredentials

    device_credentials_collection.update_one(
        {"_id": credential["_id"]},
        {"$set": {"last_used_at": datetime.now(timezone.utc)}},
    )
    user["device_name"] = credential.get("device_name")
    return user


def is_device_credential_active(user_id: str, device_id: str) -> bool:
    credential = device_credentials_collection.find_one(
        {"user_id": user_id, "device_id": device_id}
    )
    return credential is not None and credential.get("is_revoked") is not True


def list_device_credentials(user_id: str) -> list[dict[str, Any]]:
    return list(device_credentials_collection.find({"user_id": user_id}))


def revoke_device_credential(user_id: str, device_id: str) -> bool:
    now = datetime.now(timezone.utc)
    credential = device_credentials_collection.find_one(
        {"user_id": user_id, "device_id": device_id}
    )
    if credential is None:
        return False

    device_credentials_collection.update_one(
        {"_id": credential["_id"]},
        {"$set": {"is_revoked": True, "revoked_at": now}},
    )
    refresh_tokens_collection.update_many(
        {"user_id": user_id, "device_id": device_id, "revoked_at": None},
        {"$set": {"revoked_at": now, "is_active": False}},
    )
    return True


def issue_token_pair(
    user_id: str,
    device_name: str | None = None,
    device_id: str | None = None,
) -> TokenPair:
    session_id = secrets.token_urlsafe(32)
    now = datetime.now(timezone.utc)
    refresh_token, token_id, expires_at = create_refresh_token(
        user_id,
        session_id,
    )
    _insert_refresh_token(
        token=refresh_token,
        token_id=token_id,
        user_id=user_id,
        session_id=session_id,
        device_name=device_name,
        expires_at=expires_at,
        created_at=now,
        is_active=True,
        device_id=device_id,
    )
    return TokenPair(
        access_token=create_access_token(
            user_id,
            data={"did": device_id} if device_id is not None else None,
        ),
        refresh_token=refresh_token,
    )


def rotate_refresh_token(token: str) -> TokenPair:
    try:
        claims = decode_refresh_token(token)
    except (jwt.InvalidTokenError, ValueError) as error:
        raise InvalidRefreshToken from error

    user_id = claims["sub"]
    session_id = claims["sid"]
    token_id = claims["jti"]
    old_token_hash = _token_hash(token)
    current = refresh_tokens_collection.find_one(
        {
            "token_hash": old_token_hash,
            "user_id": user_id,
            "session_id": session_id,
            "token_id": token_id,
        }
    )
    if current is None:
        raise InvalidRefreshToken

    now = datetime.now(timezone.utc)
    device_id = current.get("device_id")
    if (
        current.get("revoked_at") is not None
        or current.get("is_active") is not True
        or _is_expired(current.get("expires_at"), now)
        or (
            device_id is not None
            and not is_device_credential_active(user_id, device_id)
        )
    ):
        if current.get("replaced_by") is not None:
            _revoke_session(session_id, now)
        raise InvalidRefreshToken

    _require_user(user_id)
    new_refresh_token, new_token_id, new_expires_at = create_refresh_token(
        user_id,
        session_id,
    )
    new_record_id = _insert_refresh_token(
        token=new_refresh_token,
        token_id=new_token_id,
        user_id=user_id,
        session_id=session_id,
        device_name=current.get("device_name"),
        expires_at=new_expires_at,
        created_at=now,
        is_active=False,
        device_id=current.get("device_id"),
    )

    claimed = refresh_tokens_collection.find_one_and_update(
        {
            "_id": current["_id"],
            "token_hash": old_token_hash,
            "is_active": True,
            "revoked_at": None,
            "expires_at": {"$gt": now},
        },
        {
            "$set": {
                "revoked_at": now,
                "replaced_by": new_token_id,
                "is_active": False,
            }
        },
        return_document=ReturnDocument.BEFORE,
    )
    if claimed is None:
        _revoke_session(session_id, now)
        raise InvalidRefreshToken

    activated = refresh_tokens_collection.find_one_and_update(
        {
            "_id": new_record_id,
            "is_active": False,
            "revoked_at": None,
        },
        {"$set": {"is_active": True}},
        return_document=ReturnDocument.AFTER,
    )
    if activated is None:
        _revoke_session(session_id, now)
        raise InvalidRefreshToken

    return TokenPair(
        access_token=create_access_token(
            user_id,
            data={"did": device_id} if device_id is not None else None,
        ),
        refresh_token=new_refresh_token,
    )


def revoke_refresh_session(token: str) -> None:
    try:
        claims = decode_refresh_token(token, allow_expired=True)
    except (jwt.InvalidTokenError, ValueError):
        return

    current = refresh_tokens_collection.find_one(
        {
            "token_hash": _token_hash(token),
            "user_id": claims["sub"],
            "session_id": claims["sid"],
            "token_id": claims["jti"],
        }
    )
    if current is not None:
        _revoke_session(claims["sid"])
        device_id = current.get("device_id")
        if device_id is not None:
            revoke_device_credential(current["user_id"], device_id)


def revoke_all_sessions(user_id: str) -> int:
    active_sessions = refresh_tokens_collection.distinct(
        "session_id",
        {"user_id": user_id, "revoked_at": None},
    )
    refresh_tokens_collection.update_many(
        {"user_id": user_id, "revoked_at": None},
        {
            "$set": {
                "revoked_at": datetime.now(timezone.utc),
                "is_active": False,
            }
        },
    )
    device_credentials_collection.update_many(
        {"user_id": user_id, "is_revoked": False},
        {
            "$set": {
                "is_revoked": True,
                "revoked_at": datetime.now(timezone.utc),
            }
        },
    )
    return len(active_sessions)


def token_expiration_seconds() -> tuple[int, int]:
    return ACCESS_TOKEN_EXPIRE_SECONDS, REFRESH_TOKEN_EXPIRE_SECONDS
