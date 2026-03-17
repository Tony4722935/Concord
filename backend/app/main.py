from contextlib import asynccontextmanager
import asyncio

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.database import Base, engine, run_migrations
from app.realtime import realtime_hub
from app.routers.auth import router as auth_router
from app.routers.dms import router as dms_router
from app.routers.friends import router as friends_router
from app.routers.health import router as health_router
from app.routers.servers import router as servers_router
from app.routers.uploads import router as uploads_router
from app.routers.users import router as users_router
from app.routers.ws import router as ws_router


@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(bind=engine)
    run_migrations()
    realtime_hub.set_loop(asyncio.get_running_loop())
    yield


app = FastAPI(title=settings.app_name, lifespan=lifespan)
origins = [origin.strip() for origin in settings.cors_allow_origins.split(',') if origin.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins or ['*'],
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*'],
)
app.include_router(health_router)
app.include_router(auth_router, prefix=settings.api_prefix)
app.include_router(users_router, prefix=settings.api_prefix)
app.include_router(friends_router, prefix=settings.api_prefix)
app.include_router(dms_router, prefix=settings.api_prefix)
app.include_router(servers_router, prefix=settings.api_prefix)
app.include_router(uploads_router, prefix=settings.api_prefix)
app.include_router(ws_router, prefix=settings.api_prefix)
