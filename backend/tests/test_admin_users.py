import pytest
from fastapi import HTTPException

from app.routers import admin_users, auth
from app.schemas.user import (
    AdminUserCreate,
    AdminUserUpdate,
    UserLogin,
    UserRegister,
)
from app.utils.security import decode_refresh_token
from conftest import TEST_DATABASE


PASSWORD = "correct-horse-battery-staple"


def create_admin() -> dict[str, str]:
    result = auth.users_collection.insert_one(
        {
            "name": "Admin User",
            "email": "admin@example.com",
            "password": auth.password_hash.hash(PASSWORD),
            "role": "admin",
        }
    )
    return {"id": str(result.inserted_id), "role": "admin"}


def test_registration_assigns_user_role_and_role_guard_denies_admin_access():
    auth.register_user(
        UserRegister(
            name="Example User",
            email="person@example.com",
            password=PASSWORD,
        )
    )
    stored_user = auth.users_collection.find_one({"email": "person@example.com"})
    assert stored_user is not None
    assert stored_user["role"] == "user"

    login_response = auth.login_user(
        UserLogin(email="person@example.com", password=PASSWORD)
    )
    current_user = auth.get_current_user(
        auth.HTTPAuthorizationCredentials(
            scheme="Bearer",
            credentials=login_response["access_token"],
        )
    )
    assert current_user["role"] == "user"

    with pytest.raises(HTTPException) as error:
        auth.require_role("admin")(current_user)
    assert error.value.status_code == 403


def test_admin_can_create_list_get_and_update_users():
    admin = create_admin()
    created = admin_users.create_user(
        AdminUserCreate(
            name="Managed User",
            email="managed@example.com",
            password=PASSWORD,
        ),
        admin,
    )

    stored_user = auth.users_collection.find_one({"email": created.email})
    assert stored_user is not None
    assert stored_user["password"] != PASSWORD
    assert created.role == "user"
    assert (
        admin_users.list_users(admin, skip=0, limit=50)[0].email
        == "admin@example.com"
    )
    assert admin_users.get_user(created.id, admin).id == created.id

    updated = admin_users.update_user(
        created.id,
        AdminUserUpdate(name="Updated User", role="admin"),
        admin,
    )
    assert updated.name == "Updated User"
    assert updated.role == "admin"


def test_admin_password_update_revokes_sessions_and_delete_removes_todos():
    admin = create_admin()
    created = admin_users.create_user(
        AdminUserCreate(
            name="Managed User",
            email="managed@example.com",
            password=PASSWORD,
        ),
        admin,
    )
    login_response = auth.login_user(
        UserLogin(email=created.email, password=PASSWORD)
    )

    admin_users.update_user(
        created.id,
        AdminUserUpdate(password="new-password-123"),
        admin,
    )
    refresh_record = TEST_DATABASE["refresh_tokens"].find_one(
        {"token_id": decode_refresh_token(login_response["refresh_token"])["jti"]}
    )
    assert refresh_record is not None
    assert refresh_record["revoked_at"] is not None

    TEST_DATABASE["todos"].insert_one(
        {"user_id": created.id, "title": "Private todo"}
    )
    TEST_DATABASE["chat_messages"].insert_one(
        {
            "sender_id": created.id,
            "recipient_id": admin["id"],
            "content": "Private message",
        }
    )
    admin_users.delete_user(created.id, admin)

    assert auth.users_collection.find_one({"email": created.email}) is None
    assert list(TEST_DATABASE["todos"].find({"user_id": created.id})) == []
    assert list(
        TEST_DATABASE["chat_messages"].find(
            {"sender_id": created.id}
        )
    ) == []
    with pytest.raises(HTTPException) as error:
        auth.get_current_user(
            auth.HTTPAuthorizationCredentials(
                scheme="Bearer",
                credentials=login_response["access_token"],
            )
        )
    assert error.value.status_code == 401


def test_admin_cannot_delete_or_demote_themselves():
    admin = create_admin()
    assert auth.require_role("admin")(admin) == admin

    with pytest.raises(HTTPException) as error:
        admin_users.update_user(
            admin["id"].upper(),
            AdminUserUpdate(role="user"),
            admin,
        )
    assert error.value.status_code == 409

    with pytest.raises(HTTPException) as error:
        admin_users.delete_user(admin["id"], admin)
    assert error.value.status_code == 409
