import asyncio
import json

import pytest
from fastapi import WebSocketDisconnect

from app.services import chat_service
from app.routers import auth, chat
from app.schemas.chat import ChatSocketMessage
from app.schemas.user import UserLogin, UserRegister
from app.services.chat_service import conversation_channel, save_chat_message
from conftest import TEST_DATABASE


PASSWORD = "correct-horse-battery-staple"


def register_user(name: str, email: str) -> str:
    auth.register_user(
        UserRegister(name=name, email=email, password=PASSWORD)
    )
    user = auth.users_collection.find_one({"email": email})
    assert user is not None
    return str(user["_id"])


def test_users_can_find_chat_partners_by_email_without_exposing_passwords():
    current_user_id = register_user("Alice Example", "alice@example.com")
    bob_id = register_user("Bob Example", "bob@example.com")
    register_user("Bobby Example", "bobby@example.com")

    users = chat.find_chat_users(
        "BOB@EXAMPLE",
        {"id": current_user_id, "role": "user"},
    )

    assert {user.id for user in users} == {bob_id}
    assert users[0].email == "bob@example.com"
    assert "password" not in users[0].model_dump()


def test_chat_history_is_persistent_and_visible_only_to_the_pair():
    alice_id = register_user("Alice Example", "alice@example.com")
    bob_id = register_user("Bob Example", "bob@example.com")
    charlie_id = register_user("Charlie Example", "charlie@example.com")
    save_chat_message(alice_id, bob_id, "First message")
    save_chat_message(bob_id, alice_id, "Reply")
    save_chat_message(charlie_id, bob_id, "Private to Alice's history filter")

    history = chat.get_chat_history(
        bob_id,
        {"id": alice_id, "role": "user"},
        limit=100,
    )

    assert [message.content for message in history] == [
        "First message",
        "Reply",
    ]
    assert all(
        message.sender_id in {alice_id, bob_id}
        and message.recipient_id in {alice_id, bob_id}
        for message in history
    )


def test_websocket_authenticates_and_persists_messages(monkeypatch):
    sender_id = register_user("Alice Example", "alice@example.com")
    recipient_id = register_user("Bob Example", "bob@example.com")
    login_response = auth.login_user(
        UserLogin(email="alice@example.com", password=PASSWORD)
    )
    pubsub = FakePubSub()

    async def subscribe(first_user_id: str, second_user_id: str):
        assert {first_user_id, second_user_id} == {sender_id, recipient_id}
        return pubsub

    async def publish(first_user_id: str, second_user_id: str, message: dict):
        assert {first_user_id, second_user_id} == {sender_id, recipient_id}
        await pubsub.messages.put(
            {"type": "message", "data": json.dumps(message)}
        )
        await asyncio.sleep(0)

    monkeypatch.setattr(chat, "subscribe_to_conversation", subscribe)
    monkeypatch.setattr(chat, "publish_to_conversation", publish)
    websocket = FakeWebSocket(
        [
            {
                "type": "authenticate",
                "token": login_response["access_token"],
            },
            {"type": "message", "content": "Hello Bob"},
        ]
    )

    asyncio.run(chat.chat_websocket(websocket, recipient_id))

    saved_messages = list(
        TEST_DATABASE["chat_messages"].find(
            {"sender_id": sender_id, "recipient_id": recipient_id}
        )
    )
    assert len(saved_messages) == 1
    assert saved_messages[0]["content"] == "Hello Bob"
    assert websocket.sent[0]["type"] == "ready"
    assert websocket.sent[1]["type"] == "message"
    assert websocket.sent[1]["message"]["content"] == "Hello Bob"
    assert pubsub.closed


def test_invalid_socket_token_is_rejected():
    recipient_id = register_user("Bob Example", "bob@example.com")
    websocket = FakeWebSocket(
        [{"type": "authenticate", "token": "not-a-token"}]
    )

    asyncio.run(chat.chat_websocket(websocket, recipient_id))

    assert websocket.close_code == 1008
    assert list(TEST_DATABASE["chat_messages"].find({})) == []


def test_conversation_channel_is_symmetric_and_pair_specific():
    assert conversation_channel("alice", "bob") == conversation_channel(
        "bob", "alice"
    )
    assert conversation_channel("alice", "bob") != conversation_channel(
        "alice", "charlie"
    )


def test_redis_service_subscribes_and_publishes_to_conversation_channel(
    monkeypatch,
):
    class FakeRedisClient:
        def __init__(self):
            self.pubsub_instance = FakePubSub()
            self.published: list[tuple[str, str]] = []

        def pubsub(self):
            return self.pubsub_instance

        async def publish(self, channel: str, payload: str):
            self.published.append((channel, payload))

    fake_redis = FakeRedisClient()
    monkeypatch.setattr(chat_service, "redis_client", fake_redis)
    message = {"type": "message", "message": {"content": "Hello"}}

    async def exercise_redis():
        pubsub = await chat_service.subscribe_to_conversation("alice", "bob")
        await chat_service.publish_to_conversation("bob", "alice", message)
        return pubsub

    pubsub = asyncio.run(exercise_redis())

    channel, payload = fake_redis.published[0]
    assert channel == conversation_channel("alice", "bob")
    assert json.loads(payload) == message
    assert pubsub.subscribed_channel == channel


def test_chat_message_validation_rejects_empty_content():
    with pytest.raises(ValueError):
        ChatSocketMessage(type="message", content="   ")


def test_chat_routes_are_registered_with_and_without_api_version_prefix():
    from app.main import app

    paths = app.openapi()["paths"]
    for prefix in ("/chat", "/api/v1/chat"):
        assert f"{prefix}/users" in paths
        assert f"{prefix}/{{peer_id}}/messages" in paths

    websocket_paths = {route.path for route in chat.router.routes}
    assert "/chat/ws/{peer_id}" in websocket_paths


class FakeWebSocket:
    def __init__(self, received: list[dict]) -> None:
        self.received = iter(received)
        self.sent: list[dict] = []
        self.close_code: int | None = None

    async def accept(self) -> None:
        pass

    async def receive_json(self) -> dict:
        try:
            return next(self.received)
        except StopIteration:
            raise WebSocketDisconnect(code=1000)

    async def send_json(self, message: dict) -> None:
        self.sent.append(message)

    async def send_text(self, message: str) -> None:
        self.sent.append(json.loads(message))

    async def close(self, code: int = 1000) -> None:
        self.close_code = code


class FakePubSub:
    def __init__(self) -> None:
        self.messages: asyncio.Queue[dict] = asyncio.Queue()
        self.subscribed_channel: str | None = None
        self.closed = False

    async def subscribe(self, channel: str) -> None:
        self.subscribed_channel = channel

    async def listen(self):
        while True:
            yield await self.messages.get()

    async def aclose(self) -> None:
        self.closed = True
