"""Abyssal Descent AI Server -- FastAPI entry point."""

import logging

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from config import get_settings
from routers import dungeon, npc, content, ws, game_state
from services.persistence_service import persistence_service

settings = get_settings()

logging.basicConfig(
    level=logging.DEBUG if settings.debug else logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)

logger = logging.getLogger(__name__)

# ---------- Swagger / OpenAPI metadata ----------

tags_metadata = [
    {
        "name": "npc",
        "description": "NPC 대화 및 상태 관리 -- 심연의 NPC들과 대화하고 호감도/감정 상태를 조회합니다.",
    },
    {
        "name": "dungeon",
        "description": "던전 생성 및 탐험 -- AI 기반 절차적 던전 생성과 탐험 관련 API.",
    },
    {
        "name": "content",
        "description": "콘텐츠 파이프라인 -- 게임 콘텐츠 생성 및 관리.",
    },
    {
        "name": "game_state",
        "description": "게임 상태 관리 -- 플레이어 진행 상황 저장/불러오기.",
    },
    {
        "name": "websocket",
        "description": "WebSocket 실시간 통신 -- 실시간 게임 이벤트 스트리밍.",
    },
    {
        "name": "system",
        "description": "시스템 -- 서버 상태 확인 및 관리 엔드포인트.",
    },
]


# ---------- Lifespan (startup / shutdown) ----------

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    logger.info("Abyssal Descent AI Server starting up...")
    logger.info("Persistence service initialised (data dir: ./data)")
    yield
    # Shutdown
    logger.info("Flushing persistence data to disk...")
    persistence_service.flush()
    logger.info("Abyssal Descent AI Server shut down.")


app = FastAPI(
    title="심연의 하강 AI 서버 (Abyssal Descent AI Server)",
    version=settings.app_version,
    description=(
        "**심연의 하강** 게임을 위한 AI 던전 마스터 서버입니다.\n\n"
        "던전 절차적 생성, NPC 대화 시스템, 콘텐츠 파이프라인을 제공합니다.\n\n"
        "- **NPC 대화**: 감정 및 호감도 기반 동적 대화 시스템\n"
        "- **던전 생성**: AI 기반 절차적 던전 생성\n"
        "- **콘텐츠 관리**: 게임 콘텐츠 생성 파이프라인\n"
        "- **실시간 통신**: WebSocket 기반 실시간 이벤트\n"
    ),
    openapi_tags=tags_metadata,
    lifespan=lifespan,
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.get_cors_origins(),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Routers
app.include_router(dungeon.router)
app.include_router(npc.router)
app.include_router(content.router)
app.include_router(ws.router)
app.include_router(game_state.router)


@app.get("/api/health", tags=["system"])
async def health_check() -> dict:
    """서버 상태 확인 (Health check) 엔드포인트."""
    return {
        "status": "ok",
        "version": settings.app_version,
        "service": settings.app_name,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host=settings.host, port=settings.port, reload=settings.debug)
