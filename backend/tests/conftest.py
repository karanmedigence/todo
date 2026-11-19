import os
import sys
from copy import deepcopy
from datetime import datetime, timezone
from threading import RLock
from types import ModuleType, SimpleNamespace

import pytest
from bson import ObjectId
from pymongo import ReturnDocument

os.environ["ACCESS_TOKEN_SECRET_KEY"] = "test-access-signing-secret-key-32-bytes"
os.environ["REFRESH_TOKEN_SECRET_KEY"] = "test-refresh-signing-secret-key-32-bytes"
os.environ["ACCESS_TOKEN_EXPIRE_MINUTES"] = "15"
os.environ["REFRESH_TOKEN_EXPIRE_DAYS"] = "7"


class InMemoryCollection:
    def __init__(self) -> None:
        self.documents: list[dict] = []
        self._lock = RLock()

    def insert_one(self, document: dict) -> SimpleNamespace:
        with self._lock:
            saved = self._mongo_values(document)
            saved.setdefault("_id", ObjectId())
            self.documents.append(saved)
            return SimpleNamespace(inserted_id=saved["_id"])

    def find_one(self, query: dict) -> dict | None:
        with self._lock:
            return next(
                (deepcopy(document) for document in self.documents if self._matches(document, query)),
                None,
            )

    def find_one_and_update(
        self,
        query: dict,
        update: dict,
        return_document=ReturnDocument.BEFORE,
    ) -> dict | None:
        with self._lock:
            for document in self.documents:
                if self._matches(document, query):
                    previous = deepcopy(document)
                    document.update(self._mongo_values(update.get("$set", {})))
                    result = document if return_document == ReturnDocument.AFTER else previous
                    return deepcopy(result)
        return None

    def update_many(self, query: dict, update: dict) -> SimpleNamespace:
        modified_count = 0
        with self._lock:
            for document in self.documents:
                if self._matches(document, query):
                    document.update(self._mongo_values(update.get("$set", {})))
                    modified_count += 1
        return SimpleNamespace(modified_count=modified_count)

    def update_one(self, query: dict, update: dict) -> SimpleNamespace:
        with self._lock:
            for document in self.documents:
                if self._matches(document, query):
                    document.update(self._mongo_values(update.get("$set", {})))
                    return SimpleNamespace(modified_count=1)
        return SimpleNamespace(modified_count=0)

    def find(self, query: dict) -> list[dict]:
        with self._lock:
            return [
                deepcopy(document)
                for document in self.documents
                if self._matches(document, query)
            ]

    def distinct(self, field: str, query: dict) -> list:
        with self._lock:
            return list(
                {
                    document[field]
                    for document in self.documents
                    if field in document and self._matches(document, query)
                }
            )

    @staticmethod
    def _matches(document: dict, query: dict) -> bool:
        for field, expected in query.items():
            actual = document.get(field)
            if isinstance(expected, dict):
                if "$gt" in expected and (
                    actual is None
                    or InMemoryCollection._as_utc(actual)
                    <= InMemoryCollection._as_utc(expected["$gt"])
                ):
                    return False
            elif actual != expected:
                return False
        return True

    @staticmethod
    def _mongo_values(document: dict) -> dict:
        values = deepcopy(document)
        for field, value in values.items():
            if isinstance(value, datetime) and value.tzinfo is not None:
                values[field] = value.astimezone(timezone.utc).replace(tzinfo=None)
        return values

    @staticmethod
    def _as_utc(value: datetime) -> datetime:
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)


class InMemoryDatabase:
    def __init__(self) -> None:
        self.collections = {
            "users": InMemoryCollection(),
            "refresh_tokens": InMemoryCollection(),
            "device_credentials": InMemoryCollection(),
            "todos": InMemoryCollection(),
        }

    def __getitem__(self, name: str) -> InMemoryCollection:
        return self.collections[name]

    def clear(self) -> None:
        for collection in self.collections.values():
            with collection._lock:
                collection.documents.clear()


TEST_DATABASE = InMemoryDatabase()
connection_module = ModuleType("app.db.connection")
connection_module.__dict__.update(
    {
        "database": TEST_DATABASE,
        "users_collection": TEST_DATABASE["users"],
        "refresh_tokens_collection": TEST_DATABASE["refresh_tokens"],
        "device_credentials_collection": TEST_DATABASE["device_credentials"],
    }
)
sys.modules["app.db.connection"] = connection_module


@pytest.fixture(autouse=True)
def clear_test_database():
    TEST_DATABASE.clear()
