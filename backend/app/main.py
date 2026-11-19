from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import admin_users, auth, chat, todo
from app.services.redis_service import redis_client


@asynccontextmanager
async def lifespan(_: FastAPI):
    try:
        await redis_client.ping()
        yield
    finally:
        await redis_client.aclose()


app = FastAPI(lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"^http://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(auth.router, prefix="/api/v1")
app.include_router(admin_users.router)
app.include_router(admin_users.router, prefix="/api/v1")
app.include_router(chat.router)
app.include_router(chat.router, prefix="/api/v1")
app.include_router(todo.router)


@app.get("/")
def home():
    return {"message": "TODO API is working"}
