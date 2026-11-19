
import os

from dotenv import load_dotenv
from pymongo import MongoClient

load_dotenv()

MONGO_URL = os.getenv("MONGODB_URL")
DATABASE_NAME = os.getenv("MONGODB_DATABASE")

if not MONGO_URL or not DATABASE_NAME:
    raise ValueError("MongoDB settings missing in .env")

client = MongoClient(MONGO_URL)
database = client[DATABASE_NAME]

users_collection = database["users"]
refresh_tokens_collection = database["refresh_tokens"]
device_credentials_collection = database["device_credentials"]

# Prevent duplicate email registrations
users_collection.create_index("email", unique=True)

refresh_tokens_collection.create_index("token_hash", unique=True)
refresh_tokens_collection.create_index("user_id")
refresh_tokens_collection.create_index("session_id")
refresh_tokens_collection.create_index("expires_at", expireAfterSeconds=0)
device_credentials_collection.create_index(
    [("user_id", 1), ("device_id", 1)],
    unique=True,
)

# Test connection
client.admin.command("ping")
print("MongoDB connected successfully!")
