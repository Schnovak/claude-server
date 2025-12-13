import asyncio
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .config import get_settings
from .database import init_db
from .routers import (
    auth_router,
    projects_router,
    jobs_router,
    files_router,
    git_router,
    claude_router,
)
from .services.job_runner import job_runner

settings = get_settings()

# Configure logging
logging.basicConfig(
    level=logging.DEBUG if settings.debug else logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler."""
    # Startup
    logger.info("Starting Remote Dev Platform...")

    # Initialize database
    await init_db()
    logger.info("Database initialized")

    # Ensure directories exist
    settings.users_path.mkdir(parents=True, exist_ok=True)
    settings.data_path.mkdir(parents=True, exist_ok=True)
    settings.logs_path.mkdir(parents=True, exist_ok=True)
    settings.job_logs_path.mkdir(parents=True, exist_ok=True)
    settings.artifacts_path.mkdir(parents=True, exist_ok=True)
    logger.info("Directories created")

    # Start job runner in background
    job_runner_task = asyncio.create_task(job_runner.start())
    logger.info("Job runner started")

    yield

    # Shutdown
    logger.info("Shutting down...")
    await job_runner.stop()
    job_runner_task.cancel()
    try:
        await job_runner_task
    except asyncio.CancelledError:
        pass


app = FastAPI(
    title="Remote Dev Platform",
    description="Remote development platform with Claude Code integration",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(auth_router, prefix="/api")
app.include_router(projects_router, prefix="/api")
app.include_router(jobs_router, prefix="/api")
app.include_router(files_router, prefix="/api")
app.include_router(git_router, prefix="/api")
app.include_router(claude_router, prefix="/api")


@app.get("/")
async def root():
    """Health check endpoint."""
    return {
        "status": "ok",
        "service": "Remote Dev Platform",
        "version": "1.0.0"
    }


@app.get("/api/health")
async def health_check():
    """API health check."""
    return {"status": "healthy"}


# Exception handler for debugging
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.exception(f"Unhandled exception: {exc}")
    return JSONResponse(
        status_code=500,
        content={"detail": str(exc), "type": type(exc).__name__}
    )
