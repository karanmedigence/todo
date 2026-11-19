from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import auth, todo

app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"^http://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(auth.router, prefix="/api/v1")
app.include_router(todo.router)


@app.get("/")
def home():
    return {"message": "TODO API is working"}
