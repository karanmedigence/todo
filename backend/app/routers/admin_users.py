from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from bson import ObjectId
from pymongo.errors import DuplicateKeyError

from app.db.connection import (
    chat_messages_collection,
    database,
    users_collection,
)
from app.routers.auth import password_hash, require_role
from app.schemas.user import AdminUserCreate, AdminUserResponse, AdminUserUpdate
from app.services.token_service import revoke_all_sessions

router = APIRouter(
    prefix="/admin/users",
    tags=["User administration"],
)


def _public_user(user: dict) -> AdminUserResponse:
    role = user.get("role", "user")
    if role not in {"user", "admin"}:
        role = "user"
    return AdminUserResponse(
        id=str(user["_id"]),
        name=user["name"],
        email=user["email"],
        role=role,
    )


def _find_user(user_id: str) -> dict | None:
    if not ObjectId.is_valid(user_id):
        return None
    return users_collection.find_one({"_id": ObjectId(user_id)})


def _require_user(user_id: str) -> dict:
    user = _find_user(user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )
    return user


def _is_last_admin(user: dict) -> bool:
    if user.get("role") != "admin":
        return False
    return len(list(users_collection.find({"role": "admin"}))) <= 1


@router.post(
    "",
    response_model=AdminUserResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_user(
    request: AdminUserCreate,
    _current_user: dict[str, str] = Depends(require_role("admin")),
) -> AdminUserResponse:
    if users_collection.find_one({"email": request.email}) is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered",
        )

    user_document = {
        "name": request.name,
        "email": request.email,
        "password": password_hash.hash(request.password),
        "role": request.role,
    }
    try:
        result = users_collection.insert_one(user_document)
    except DuplicateKeyError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered",
        )

    return _public_user({**user_document, "_id": result.inserted_id})


@router.get("", response_model=list[AdminUserResponse])
def list_users(
    _current_user: dict[str, str] = Depends(require_role("admin")),
    skip: int = Query(default=0, ge=0),
    limit: int = Query(default=50, ge=1, le=100),
) -> list[AdminUserResponse]:
    users = users_collection.find({}).skip(skip).limit(limit)
    return [_public_user(user) for user in users]


@router.get("/{user_id}", response_model=AdminUserResponse)
def get_user(
    user_id: str,
    _current_user: dict[str, str] = Depends(require_role("admin")),
) -> AdminUserResponse:
    return _public_user(_require_user(user_id))


@router.patch("/{user_id}", response_model=AdminUserResponse)
def update_user(
    user_id: str,
    request: AdminUserUpdate,
    current_user: dict[str, str] = Depends(require_role("admin")),
) -> AdminUserResponse:
    user = _require_user(user_id)
    canonical_user_id = str(user["_id"])
    updates = request.model_dump(exclude_unset=True)
    new_role = updates.get("role", user.get("role", "user"))

    if (
        canonical_user_id == current_user["id"]
        and new_role != user.get("role", "user")
    ):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="You cannot change your own role",
        )
    if user.get("role") == "admin" and new_role != "admin" and _is_last_admin(user):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="The last admin cannot be demoted",
        )

    email = updates.get("email")
    if email is not None:
        existing_user = users_collection.find_one({"email": email})
        if existing_user is not None and existing_user["_id"] != user["_id"]:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Email already registered",
            )

    password = updates.pop("password", None)
    if password is not None:
        updates["password"] = password_hash.hash(password)

    try:
        users_collection.update_one({"_id": user["_id"]}, {"$set": updates})
    except DuplicateKeyError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered",
        )

    if password is not None:
        revoke_all_sessions(canonical_user_id)

    return _public_user(_require_user(canonical_user_id))


@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_user(
    user_id: str,
    current_user: dict[str, str] = Depends(require_role("admin")),
) -> Response:
    user = _require_user(user_id)
    canonical_user_id = str(user["_id"])
    if canonical_user_id == current_user["id"]:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="You cannot delete your own account",
        )
    if _is_last_admin(user):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="The last admin cannot be deleted",
        )

    revoke_all_sessions(canonical_user_id)
    database["todos"].delete_many({"user_id": canonical_user_id})
    chat_messages_collection.delete_many(
        {
            "$or": [
                {"sender_id": canonical_user_id},
                {"recipient_id": canonical_user_id},
            ]
        }
    )
    users_collection.delete_one({"_id": user["_id"]})
    return Response(status_code=status.HTTP_204_NO_CONTENT)
