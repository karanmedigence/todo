import asyncio
import json

from bson import ObjectId
from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Query,
    WebSocket,
    WebSocketDisconnect,
    status,
)
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import ValidationError
from pymongo.errors import PyMongoError
from redis.asyncio.client import PubSub
from redis.exceptions import RedisError

from app.db.connection import users_collection
from app.routers.auth import get_current_user
from app.schemas.chat import (
    ChatMessageResponse,
    ChatSocketAuth,
    ChatSocketMessage,
    ChatUserResponse,
)
from app.services.chat_service import (
    list_chat_messages,
    publish_to_conversation,
    relay_conversation_messages,
    save_chat_message,
    search_chat_users,
    subscribe_to_conversation,
)

router = APIRouter(prefix="/chat", tags=["Chat"])


def _require_peer(peer_id: str, current_user_id: str) -> str:
    if not ObjectId.is_valid(peer_id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Chat user not found",
        )

    peer_object_id = ObjectId(peer_id)
    if str(peer_object_id) == current_user_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You cannot start a chat with yourself",
        )

    peer = users_collection.find_one({"_id": peer_object_id}, {"_id": 1})
    if peer is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Chat user not found",
        )
    return str(peer["_id"])


@router.get("/users", response_model=list[ChatUserResponse])
def find_chat_users(
    search: str = Query(min_length=3, max_length=254),
    current_user: dict[str, str] = Depends(get_current_user),
) -> list[ChatUserResponse]:
    return search_chat_users(search, current_user["id"])


@router.get("/{peer_id}/messages", response_model=list[ChatMessageResponse])
def get_chat_history(
    peer_id: str,
    current_user: dict[str, str] = Depends(get_current_user),
    limit: int = Query(default=100, ge=1, le=100),
) -> list[ChatMessageResponse]:
    peer_user_id = _require_peer(peer_id, current_user["id"])
    return list_chat_messages(current_user["id"], peer_user_id, limit)


@router.websocket("/ws/{peer_id}")
async def chat_websocket(websocket: WebSocket, peer_id: str) -> None:
    await websocket.accept()
    current_user_id: str | None = None
    peer_user_id: str | None = None
    pubsub: PubSub | None = None
    relay_task: asyncio.Task[None] | None = None

    try:
        try:
            authentication_payload = await asyncio.wait_for(
                websocket.receive_json(),
                timeout=10,
            )
            authentication = ChatSocketAuth.model_validate(authentication_payload)
        except json.JSONDecodeError:
            await websocket.close(code=1003)
            return
        except TimeoutError:
            await websocket.close(code=1008)
            return
        except ValidationError:
            await websocket.close(code=1008)
            return

        try:
            current_user = get_current_user(
                HTTPAuthorizationCredentials(
                    scheme="Bearer",
                    credentials=authentication.token,
                )
            )
        except HTTPException:
            await websocket.close(code=1008)
            return

        try:
            peer_user_id = _require_peer(peer_id, current_user["id"])
        except HTTPException:
            await websocket.close(code=1008)
            return

        current_user_id = current_user["id"]
        try:
            pubsub = await subscribe_to_conversation(
                current_user_id,
                peer_user_id,
            )
        except RedisError:
            await websocket.close(code=1011)
            return

        relay_task = asyncio.create_task(
            relay_conversation_messages(pubsub, websocket)
        )
        await websocket.send_json(
            {
                "type": "ready",
                "user_id": current_user_id,
                "peer_id": peer_user_id,
            }
        )

        while True:
            try:
                payload = await websocket.receive_json()
            except json.JSONDecodeError:
                await websocket.send_json(
                    {"type": "error", "detail": "Message must be valid JSON."}
                )
                continue

            try:
                message_request = ChatSocketMessage.model_validate(payload)
            except ValidationError:
                await websocket.send_json(
                    {
                        "type": "error",
                        "detail": "A message must contain 1 to 4000 characters.",
                    }
                )
                continue

            try:
                message = save_chat_message(
                    current_user_id,
                    peer_user_id,
                    message_request.content,
                )
            except PyMongoError:
                await websocket.send_json(
                    {
                        "type": "error",
                        "detail": "Message could not be saved. Please try again.",
                    }
                )
                continue

            try:
                await publish_to_conversation(
                    current_user_id,
                    peer_user_id,
                    {
                        "type": "message",
                        "message": message.model_dump(mode="json"),
                    },
                )
            except RedisError:
                await websocket.send_json(
                    {
                        "type": "error",
                        "detail": (
                            "Message was saved, but live delivery is "
                            "temporarily unavailable."
                        ),
                    }
                )
    except WebSocketDisconnect:
        pass
    finally:
        if relay_task is not None:
            relay_task.cancel()
            try:
                await relay_task
            except asyncio.CancelledError:
                pass
        if pubsub is not None:
            await pubsub.aclose()
