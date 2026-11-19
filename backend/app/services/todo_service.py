# app/services/todo_service.py

from datetime import datetime, timezone
from typing import Any, Mapping, Optional

from bson import ObjectId
from pymongo import ReturnDocument
from app.db.connection import database
from app.schemas.todo_schema import TodoCreate, TodoResponse, TodoUpdate


todo_collection = database["todos"]


def create_todo(todo_data: TodoCreate, user_id: str) -> TodoResponse:
    now = datetime.now(timezone.utc)
    todo = {
        "title": todo_data.title,
        "description": todo_data.description,
        "is_completed": False,
        "user_id": user_id,
        "created_at": now,
        "updated_at": now,
    }

    result = todo_collection.insert_one(todo)

    return TodoResponse(
        id=str(result.inserted_id),
        title=todo["title"],
        description=todo["description"],
        is_completed=todo["is_completed"],
    )


def _todo_filter(todo_id: str, user_id: str) -> Optional[dict[str, object]]:
    if not ObjectId.is_valid(todo_id):
        return None
    return {"_id": ObjectId(todo_id), "user_id": user_id}


def _to_response(todo: Mapping[str, Any]) -> TodoResponse:
    return TodoResponse(
        id=str(todo["_id"]),
        title=todo["title"],
        description=todo.get("description"),
        is_completed=todo["is_completed"],
    )


def list_todos(user_id: str) -> list[TodoResponse]:
    todos = todo_collection.find({"user_id": user_id}).sort("created_at", -1)
    return [_to_response(todo) for todo in todos]


def get_todo(todo_id: str, user_id: str) -> Optional[TodoResponse]:
    todo_filter = _todo_filter(todo_id, user_id)
    if todo_filter is None:
        return None

    todo = todo_collection.find_one(todo_filter)
    return _to_response(todo) if todo is not None else None


def update_todo(
    todo_id: str,
    todo_data: TodoUpdate,
    user_id: str,
) -> Optional[TodoResponse]:
    todo_filter = _todo_filter(todo_id, user_id)
    if todo_filter is None:
        return None

    updated_todo = todo_collection.find_one_and_update(
        todo_filter,
        {
            "$set": {
                **todo_data.model_dump(exclude_unset=True),
                "updated_at": datetime.now(timezone.utc),
            }
        },
        return_document=ReturnDocument.AFTER,
    )
    return _to_response(updated_todo) if updated_todo is not None else None


def delete_todo(todo_id: str, user_id: str) -> bool:
    todo_filter = _todo_filter(todo_id, user_id)
    if todo_filter is None:
        return False
    return todo_collection.delete_one(todo_filter).deleted_count == 1