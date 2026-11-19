import hashlib
import secrets
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import jwt
import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from app.routers import auth
from app.schemas.user import (
    LogoutRequest,
    DeviceLoginRequest,
    RefreshTokenRequest,
    UserLogin,
    UserRegister,
)
from app.services import token_service
from app.utils.security import (
    ACCESS_TOKEN_EXPIRE_SECONDS,
    ACCESS_TOKEN_SECRET_KEY,
    ALGORITHM,
    REFRESH_TOKEN_EXPIRE_SECONDS,
    REFRESH_TOKEN_SECRET_KEY,
    decode_refresh_token,
)
from conftest import TEST_DATABASE


PASSWORD = "correct-horse-battery-staple"
EMAIL = "person@example.com"


def register_user(email: str = EMAIL) -> dict:
    return auth.register_user(
        UserRegister(name="Example User", email=email, password=PASSWORD)
    )


def login_user(
    email: str = EMAIL,
    device_name: str | None = None,
    device_id=None,
    device_secret: str | None = None,
) -> dict:
    return auth.login_user(
        UserLogin(
            email=email,
            password=PASSWORD,
            device_name=device_name,
            device_id=device_id,
            device_secret=device_secret,
        )
    )


def bearer(token: str) -> HTTPAuthorizationCredentials:
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)


def test_registration_and_login_issue_hashed_refresh_session():
    registered = register_user()
    user_document = auth.users_collection.find_one({"email": EMAIL})
    assert user_document is not None
    assert registered["id"] == str(user_document["_id"])
    assert user_document["password"] != PASSWORD

    response = login_user(device_name="Laptop")
    access_claims = jwt.decode(
        response["access_token"],
        ACCESS_TOKEN_SECRET_KEY,
        algorithms=[ALGORITHM],
    )
    refresh_claims = decode_refresh_token(response["refresh_token"])

    assert response["token_type"] == "bearer"
    assert response["expires_in"] == ACCESS_TOKEN_EXPIRE_SECONDS
    assert response["refresh_expires_in"] == REFRESH_TOKEN_EXPIRE_SECONDS
    assert access_claims["token_type"] == "access"
    assert refresh_claims["token_type"] == "refresh"

    refresh_record = TEST_DATABASE["refresh_tokens"].find_one(
        {
            "token_hash": hashlib.sha256(
                response["refresh_token"].encode("utf-8")
            ).hexdigest()
        }
    )
    assert refresh_record is not None
    assert refresh_record["device_name"] == "Laptop"
    assert response["refresh_token"] not in str(refresh_record)


def test_access_token_authenticates_me_but_refresh_token_does_not():
    register_user()
    response = login_user()

    current_user = auth.get_current_user(bearer(response["access_token"]))
    assert current_user["email"] == EMAIL
    assert auth.get_me(current_user).id == current_user["id"]

    with pytest.raises(HTTPException) as error:
        auth.get_current_user(bearer(response["refresh_token"]))
    assert error.value.status_code == 401

    with pytest.raises(HTTPException) as error:
        auth.refresh_tokens(RefreshTokenRequest(refresh_token=response["access_token"]))
    assert error.value.status_code == 401


def test_refresh_rotates_hash_and_rejects_reuse():
    register_user()
    login_response = login_user(device_name="Phone")
    old_token = login_response["refresh_token"]
    old_hash = hashlib.sha256(old_token.encode("utf-8")).hexdigest()

    rotated = auth.refresh_tokens(RefreshTokenRequest(refresh_token=old_token))
    old_record = TEST_DATABASE["refresh_tokens"].find_one(
        {"token_hash": old_hash}
    )
    new_hash = hashlib.sha256(rotated.refresh_token.encode("utf-8")).hexdigest()
    new_record = TEST_DATABASE["refresh_tokens"].find_one(
        {"token_hash": new_hash}
    )

    assert old_record is not None
    assert new_record is not None
    assert old_record["revoked_at"] is not None
    assert old_record["replaced_by"] == decode_refresh_token(rotated.refresh_token)["jti"]
    assert new_record["is_active"] is True
    assert new_record["session_id"] == old_record["session_id"]

    with pytest.raises(HTTPException) as error:
        auth.refresh_tokens(RefreshTokenRequest(refresh_token=old_token))
    assert error.value.status_code == 401
    new_record_after_reuse = TEST_DATABASE["refresh_tokens"].find_one(
        {"token_hash": new_hash}
    )
    assert new_record_after_reuse is not None
    assert new_record_after_reuse["revoked_at"] is not None


def test_device_credentials_enable_silent_login_and_revoke_current_access():
    register_user()
    device_id = uuid4()
    device_secret = secrets.token_urlsafe(48)
    password_login = login_user(
        device_name="Phone",
        device_id=device_id,
        device_secret=device_secret,
    )
    credential = TEST_DATABASE["device_credentials"].find_one(
        {"user_id": password_login["id"], "device_id": str(device_id)}
    )
    assert credential is not None
    assert credential["device_secret_hash"] == hashlib.sha256(
        device_secret.encode("utf-8")
    ).hexdigest()
    assert device_secret not in str(credential)

    with pytest.raises(HTTPException) as error:
        auth.device_login(
            DeviceLoginRequest(
                user_id=password_login["id"],
                device_id=device_id,
                device_secret=secrets.token_urlsafe(48),
            )
        )
    assert error.value.status_code == 401

    device_login = auth.device_login(
        DeviceLoginRequest(
            user_id=password_login["id"],
            device_id=device_id,
            device_secret=device_secret,
        )
    )
    refresh_record = TEST_DATABASE["refresh_tokens"].find_one(
        {
            "token_hash": hashlib.sha256(
                device_login.refresh_token.encode("utf-8")
            ).hexdigest()
        }
    )
    assert refresh_record is not None
    assert refresh_record["device_id"] == str(device_id)

    rotated = auth.refresh_tokens(
        RefreshTokenRequest(refresh_token=device_login.refresh_token)
    )
    assert jwt.decode(
        rotated.access_token,
        ACCESS_TOKEN_SECRET_KEY,
        algorithms=[ALGORITHM],
    )["did"] == str(device_id)

    auth.logout(LogoutRequest(refresh_token=rotated.refresh_token))
    with pytest.raises(HTTPException) as error:
        auth.get_current_user(bearer(rotated.access_token))
    assert error.value.status_code == 401

    with pytest.raises(HTTPException) as error:
        auth.device_login(
            DeviceLoginRequest(
                user_id=password_login["id"],
                device_id=device_id,
                device_secret=device_secret,
            )
        )
    assert error.value.status_code == 403


def test_user_can_list_and_revoke_a_device_from_another_device():
    register_user()
    revoked_device_id = uuid4()
    active_device_id = uuid4()
    revoked_secret = secrets.token_urlsafe(48)
    active_secret = secrets.token_urlsafe(48)
    revoked_device = login_user(
        device_name="Lost phone",
        device_id=revoked_device_id,
        device_secret=revoked_secret,
    )
    active_device = login_user(
        device_name="Current phone",
        device_id=active_device_id,
        device_secret=active_secret,
    )

    devices = auth.get_devices({"id": active_device["id"]}).devices
    assert {device.device_id for device in devices} == {
        str(revoked_device_id),
        str(active_device_id),
    }

    response = auth.revoke_device(
        revoked_device_id,
        {"id": active_device["id"]},
    )
    assert response.message == "Device revoked"

    with pytest.raises(HTTPException) as error:
        auth.get_current_user(bearer(revoked_device["access_token"]))
    assert error.value.status_code == 401

    with pytest.raises(HTTPException) as error:
        auth.device_login(
            DeviceLoginRequest(
                user_id=revoked_device["id"],
                device_id=revoked_device_id,
                device_secret=revoked_secret,
            )
        )
    assert error.value.status_code == 403

    assert auth.device_login(
        DeviceLoginRequest(
            user_id=active_device["id"],
            device_id=active_device_id,
            device_secret=active_secret,
        )
    ).refresh_token


def test_logout_all_revokes_silent_device_login_credentials():
    register_user()
    device_id = uuid4()
    device_secret = secrets.token_urlsafe(48)
    login_response = login_user(
        device_id=device_id,
        device_secret=device_secret,
    )

    auth.logout_all({"id": login_response["id"]})
    with pytest.raises(HTTPException) as error:
        auth.device_login(
            DeviceLoginRequest(
                user_id=login_response["id"],
                device_id=device_id,
                device_secret=device_secret,
            )
        )
    assert error.value.status_code == 403


def test_invalid_and_expired_refresh_tokens_are_rejected():
    register_user()
    login_response = login_user()
    with pytest.raises(HTTPException) as error:
        auth.refresh_tokens(RefreshTokenRequest(refresh_token="not-a-jwt"))
    assert error.value.status_code == 401

    now = datetime.now(timezone.utc)
    expired_token = jwt.encode(
        {
            "sub": login_response["id"],
            "token_type": "refresh",
            "sid": "expired-session",
            "jti": "expired-token",
            "iat": now - timedelta(days=8),
            "exp": now - timedelta(days=1),
        },
        REFRESH_TOKEN_SECRET_KEY,
        algorithm=ALGORITHM,
    )
    with pytest.raises(HTTPException) as error:
        auth.refresh_tokens(RefreshTokenRequest(refresh_token=expired_token))
    assert error.value.status_code == 401


def test_logout_is_scoped_to_one_device_and_idempotent():
    register_user()
    phone_session = login_user(device_name="Phone")
    laptop_session = login_user(device_name="Laptop")

    assert auth.logout(
        LogoutRequest(refresh_token=phone_session["refresh_token"])
    ).message == "Logged out"
    assert auth.logout(
        LogoutRequest(refresh_token=phone_session["refresh_token"])
    ).message == "Logged out"
    with pytest.raises(HTTPException):
        auth.refresh_tokens(
            RefreshTokenRequest(refresh_token=phone_session["refresh_token"])
        )

    assert auth.refresh_tokens(
        RefreshTokenRequest(refresh_token=laptop_session["refresh_token"])
    ).refresh_token


def test_logout_all_revokes_every_device_session():
    register_user()
    first_session = login_user(device_name="Phone")
    second_session = login_user(device_name="Laptop")

    response = auth.logout_all({"id": first_session["id"]})
    assert response.revoked_sessions == 2
    for login_response in (first_session, second_session):
        with pytest.raises(HTTPException):
            auth.refresh_tokens(
                RefreshTokenRequest(
                    refresh_token=login_response["refresh_token"]
                )
            )


def test_auth_routes_are_available_with_and_without_api_version_prefix():
    from app.main import app

    paths = app.openapi()["paths"]
    for prefix in ("/auth", "/api/v1/auth"):
        assert f"{prefix}/register" in paths
        assert f"{prefix}/login" in paths
        assert f"{prefix}/refresh" in paths
        assert f"{prefix}/logout" in paths
        assert f"{prefix}/logout-all" in paths
        assert f"{prefix}/me" in paths
        assert f"{prefix}/device-login" in paths
        assert f"{prefix}/devices" in paths
        assert f"{prefix}/devices/{{device_id}}" in paths


def test_concurrent_refresh_requests_cannot_create_active_descendants():
    register_user()
    login_response = login_user()
    old_token = login_response["refresh_token"]
    barrier = threading.Barrier(2)
    original_collection = TEST_DATABASE["refresh_tokens"]

    class BarrierCollection:
        def __getattr__(self, name):
            return getattr(original_collection, name)

        def find_one(self, query):
            result = original_collection.find_one(query)
            if "token_hash" in query and result and result["is_active"]:
                barrier.wait(timeout=5)
            return result

    token_service.refresh_tokens_collection = BarrierCollection()

    def rotate() -> bool:
        try:
            token_service.rotate_refresh_token(old_token)
            return True
        except token_service.InvalidRefreshToken:
            return False

    try:
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(lambda _: rotate(), range(2)))
    finally:
        token_service.refresh_tokens_collection = original_collection

    session_id = decode_refresh_token(old_token)["sid"]
    session_records = [
        record
        for record in TEST_DATABASE["refresh_tokens"].documents
        if record["session_id"] == session_id
    ]
    assert sum(results) <= 1
    assert not any(
        record["is_active"] and record["revoked_at"] is None
        for record in session_records
    )
