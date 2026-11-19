import hashlib
import hmac
import os
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
from dotenv import find_dotenv, load_dotenv

load_dotenv(find_dotenv())

ALGORITHM = "HS256"


def _validated_secret(secret_name: str, secret: str | None) -> str:
    if not secret:
        raise ValueError(f"{secret_name} is missing")
    if len(secret.encode("utf-8")) < 32:
        raise ValueError(f"{secret_name} must be at least 32 characters long")
    return secret


_legacy_secret = os.getenv("SECRET_KEY")
ACCESS_TOKEN_SECRET_KEY = _validated_secret(
    "ACCESS_TOKEN_SECRET_KEY",
    os.getenv("ACCESS_TOKEN_SECRET_KEY") or _legacy_secret,
)

_refresh_secret = os.getenv("REFRESH_TOKEN_SECRET_KEY")
if not _refresh_secret:
    _refresh_secret = hmac.new(
        ACCESS_TOKEN_SECRET_KEY.encode("utf-8"),
        b"todo-refresh-token-signing-key",
        hashlib.sha256,
    ).hexdigest()
REFRESH_TOKEN_SECRET_KEY = _validated_secret(
    "REFRESH_TOKEN_SECRET_KEY",
    _refresh_secret,
)
if REFRESH_TOKEN_SECRET_KEY == ACCESS_TOKEN_SECRET_KEY:
    raise ValueError("Access and refresh token secrets must be different")


def _positive_int_setting(name: str, default: int) -> int:
    raw_value = os.getenv(name)
    try:
        value = int(raw_value) if raw_value is not None else default
    except ValueError as error:
        raise ValueError(f"{name} must be a positive integer") from error
    if value <= 0:
        raise ValueError(f"{name} must be a positive integer")
    return value


ACCESS_TOKEN_EXPIRE_MINUTES = _positive_int_setting(
    "ACCESS_TOKEN_EXPIRE_MINUTES",
    15,
)
REFRESH_TOKEN_EXPIRE_DAYS = _positive_int_setting(
    "REFRESH_TOKEN_EXPIRE_DAYS",
    7,
)
ACCESS_TOKEN_EXPIRE_SECONDS = ACCESS_TOKEN_EXPIRE_MINUTES * 60
REFRESH_TOKEN_EXPIRE_SECONDS = REFRESH_TOKEN_EXPIRE_DAYS * 24 * 60 * 60


def create_access_token(
    user_id: str | None = None,
    *,
    data: dict[str, Any] | None = None,
    expires_delta: timedelta | None = None,
) -> str:
    payload = dict(data or {})
    if user_id is not None:
        payload.setdefault("sub", user_id)
    subject = payload.get("sub")
    if not isinstance(subject, str) or not subject:
        raise ValueError("User identifier is required")

    issued_at = datetime.now(timezone.utc)
    expires_at = issued_at + (
        expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    payload.update(
        {
            "sub": subject,
            "token_type": "access",
            "jti": secrets.token_urlsafe(32),
            "iat": issued_at,
            "exp": expires_at,
        }
    )
    return jwt.encode(payload, key=ACCESS_TOKEN_SECRET_KEY, algorithm=ALGORITHM)


def create_refresh_token(
    user_id: str,
    session_id: str,
) -> tuple[str, str, datetime]:
    issued_at = datetime.now(timezone.utc)
    expires_at = issued_at + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    token_id = secrets.token_urlsafe(32)
    payload = {
        "sub": user_id,
        "token_type": "refresh",
        "sid": session_id,
        "jti": token_id,
        "iat": issued_at,
        "exp": expires_at,
    }
    token = jwt.encode(
        payload,
        key=REFRESH_TOKEN_SECRET_KEY,
        algorithm=ALGORITHM,
    )
    return token, token_id, expires_at


def decode_access_token_claims(token: str) -> dict[str, Any]:
    payload = jwt.decode(
        token,
        key=ACCESS_TOKEN_SECRET_KEY,
        algorithms=[ALGORITHM],
        options={"require": ["exp", "sub", "iat", "jti", "token_type"]},
    )
    if payload.get("token_type") != "access":
        raise ValueError("Invalid token type")

    subject = payload.get("sub")
    if not isinstance(subject, str) or not subject:
        raise ValueError("Token missing subject claim")
    return payload


def decode_access_token(token: str) -> str:
    return decode_access_token_claims(token)["sub"]


def decode_refresh_token(
    token: str,
    *,
    allow_expired: bool = False,
) -> dict[str, Any]:
    payload = jwt.decode(
        token,
        key=REFRESH_TOKEN_SECRET_KEY,
        algorithms=[ALGORITHM],
        options={
            "require": ["exp", "sub", "iat", "jti", "sid", "token_type"],
            "verify_exp": not allow_expired,
        },
    )
    if payload.get("token_type") != "refresh":
        raise ValueError("Invalid token type")
    if not isinstance(payload.get("sub"), str) or not payload["sub"]:
        raise ValueError("Token missing subject claim")
    if not isinstance(payload.get("jti"), str) or not payload["jti"]:
        raise ValueError("Token missing identifier claim")
    if not isinstance(payload.get("sid"), str) or not payload["sid"]:
        raise ValueError("Token missing session claim")
    return payload
