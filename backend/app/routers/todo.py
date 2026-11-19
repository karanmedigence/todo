from fastapi import APIRouter, Depends, HTTPException, Response, status

from app.routers.auth import get_current_user
from app.schemas.todo_schema import TodoCreate, TodoResponse, TodoUpdate
from app.services.todo_service import (
    create_todo as save_todo,
    delete_todo as remove_todo,
    get_todo as find_todo,
    list_todos as find_todos,
    update_todo as save_todo_update,
)

router = APIRouter(
    prefix="/todos",
    tags=["Todos"],
)


@router.post("/", response_model=TodoResponse, status_code=status.HTTP_201_CREATED)
def create_todo(
    todo: TodoCreate,
    current_user: dict[str, str] = Depends(get_current_user),
) -> TodoResponse:
    return save_todo(todo, current_user["id"])


@router.get("/", response_model=list[TodoResponse])
def get_todos(
    current_user: dict[str, str] = Depends(get_current_user),
) -> list[TodoResponse]:
    return find_todos(current_user["id"])


@router.get("/{todo_id}", response_model=TodoResponse)
def get_todo(
    todo_id: str,
    current_user: dict[str, str] = Depends(get_current_user),
) -> TodoResponse:
    todo = find_todo(todo_id, current_user["id"])
    if todo is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Todo not found",
        )
    return todo


@router.put("/{todo_id}", response_model=TodoResponse)
def update_todo(
    todo_id: str,
    todo: TodoUpdate,
    current_user: dict[str, str] = Depends(get_current_user),
) -> TodoResponse:
    if not todo.model_dump(exclude_unset=True):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="At least one todo field must be provided",
        )

    updated_todo = save_todo_update(todo_id, todo, current_user["id"])
    if updated_todo is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Todo not found",
        )
    return updated_todo


@router.delete(
    "/{todo_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
def delete_todo(
    todo_id: str,
    current_user: dict[str, str] = Depends(get_current_user),
) -> Response:
    if not remove_todo(todo_id, current_user["id"]):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Todo not found",
        )
    return Response(status_code=status.HTTP_204_NO_CONTENT)