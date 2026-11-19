import json
import re
from datetime import datetime, timezone

from bson import ObjectId
from fastapi import WebSocket, WebSocketDisconnect
from redis.asyncio.client import PubSub
from redis.exceptions import RedisError

from app.db.connection import chat_messages_collection, users_collection
from app.schemas.chat import ChatMessageResponse, ChatUserResponse
from app.services.redis_service import redis_client


def search_chat_users(search: str, current_user_id: str) -> list[ChatUserResponse]:
    query = {
        "_id": {"$ne": ObjectId(current_user_id)},
        "email": {
            "$regex": re.escape(search.strip()),
            "$options": "i",
        },
    }
    users = users_collection.find(
        query,
        {"_id": 1, "name": 1, "email": 1},
    ).limit(20)
    return [
        ChatUserResponse(
            id=str(user["_id"]),
            name=user["name"],
            email=user["email"],
        )
        for user in users
    ]


def list_chat_messages(
    current_user_id: str,
    peer_id: str,
    limit: int,
) -> list[ChatMessageResponse]:
    query = {
        "$or": [
            {"sender_id": current_user_id, "recipient_id": peer_id},
            {"sender_id": peer_id, "recipient_id": current_user_id},
        ],
    }
    messages = list(
        chat_messages_collection.find(query)
        .sort("created_at", -1)
        .limit(limit)
    )
    messages.reverse()
    return [
        ChatMessageResponse(
            id=str(message["_id"]),
            sender_id=message["sender_id"],
            recipient_id=message["recipient_id"],
            content=message["content"],
            created_at=message["created_at"],
        )
        for message in messages
    ]


def save_chat_message(
    sender_id: str,
    recipient_id: str,
    content: str,
) -> ChatMessageResponse:
    document = {
        "sender_id": sender_id,
        "recipient_id": recipient_id,
        "content": content,
        "created_at": datetime.now(timezone.utc),
    }
    result = chat_messages_collection.insert_one(document)
    return ChatMessageResponse(
        id=str(result.inserted_id),
        **document,
    )


def conversation_channel(first_user_id: str, second_user_id: str) -> str:
    first, second = sorted((first_user_id, second_user_id))
    return f"chat:conversation:{first}:{second}"


async def subscribe_to_conversation(
    first_user_id: str,
    second_user_id: str,
) -> PubSub:
    pubsub = redis_client.pubsub()
    try:
        await pubsub.subscribe(
            conversation_channel(first_user_id, second_user_id)
        )
    except RedisError:
        await pubsub.aclose()
        raise
    return pubsub


async def publish_to_conversation(
    first_user_id: str,
    second_user_id: str,
    message: dict[str, object],
) -> None:
    await redis_client.publish(
        conversation_channel(first_user_id, second_user_id),
        json.dumps(message),
    )


async def relay_conversation_messages(
    pubsub: PubSub,
    websocket: WebSocket,
) -> None:
    try:
        async for event in pubsub.listen():
            if event.get("type") != "message":
                continue
            payload = event.get("data")
            if isinstance(payload, str):
                await websocket.send_text(payload)
    except (RuntimeError, WebSocketDisconnect):
        return
    except RedisError:
        try:
            await websocket.send_json(
                {
                    "type": "error",
                    "detail": "Live chat delivery is temporarily unavailable.",
                }
            )
            await websocket.close(code=1011)
        except (RuntimeError, WebSocketDisconnect):
            return
