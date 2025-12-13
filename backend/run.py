#!/usr/bin/env python3
"""
Run the Remote Dev Platform backend server.
"""
import uvicorn
import sys
from pathlib import Path

# Add the app directory to the path
sys.path.insert(0, str(Path(__file__).parent))

from app.config import get_settings

settings = get_settings()

if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
        log_level="debug" if settings.debug else "info",
    )
