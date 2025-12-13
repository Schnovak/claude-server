import asyncio
import logging
import threading
from pathlib import Path
from typing import Dict, Set, Callable, Optional
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler, FileSystemEvent

logger = logging.getLogger(__name__)


class ProjectFileHandler(FileSystemEventHandler):
    """Handler for file system events in a project directory."""

    def __init__(self, project_id: str, callback: Callable[[str, str, str], None], loop: asyncio.AbstractEventLoop):
        self.project_id = project_id
        self.callback = callback
        self._loop = loop
        self._pending_events: Dict[str, float] = {}
        self._lock = threading.Lock()

    def on_any_event(self, event: FileSystemEvent):
        # Skip directory events
        if event.is_directory:
            return

        src_path = str(event.src_path)

        # Skip .git internal files (but not .gitignore etc)
        if '/.git/' in src_path or '\\.git\\' in src_path:
            return

        event_type = event.event_type  # created, modified, deleted, moved

        # Thread-safe callback scheduling
        try:
            self._loop.call_soon_threadsafe(
                self.callback, self.project_id, event_type, src_path
            )
        except Exception as e:
            logger.error(f"Failed to schedule callback: {e}")


class FileWatcherService:
    """Service to watch project directories for file changes."""

    def __init__(self):
        self._observers: Dict[str, Observer] = {}
        self._handlers: Dict[str, ProjectFileHandler] = {}
        self._callbacks: Dict[str, Set[Callable]] = {}
        self._lock = threading.Lock()
        self._loop: Optional[asyncio.AbstractEventLoop] = None

    def _get_loop(self) -> asyncio.AbstractEventLoop:
        """Get the event loop, caching it for later use."""
        if self._loop is None:
            try:
                self._loop = asyncio.get_running_loop()
            except RuntimeError:
                self._loop = asyncio.get_event_loop()
        return self._loop

    async def watch_project(self, project_id: str, project_path: Path) -> bool:
        """Start watching a project directory."""
        loop = self._get_loop()

        with self._lock:
            if project_id in self._observers:
                return True  # Already watching

            if not project_path.exists():
                logger.warning(f"Project path does not exist: {project_path}")
                return False

            try:
                handler = ProjectFileHandler(project_id, self._on_file_change, loop)
                observer = Observer()
                observer.schedule(handler, str(project_path), recursive=True)
                observer.start()

                self._observers[project_id] = observer
                self._handlers[project_id] = handler
                self._callbacks[project_id] = set()

                logger.info(f"Started watching project {project_id} at {project_path}")
                return True
            except Exception as e:
                logger.error(f"Failed to start watching project {project_id}: {e}")
                return False

    async def stop_watching(self, project_id: str):
        """Stop watching a project directory."""
        with self._lock:
            if project_id not in self._observers:
                return

            observer = self._observers.pop(project_id)
            self._handlers.pop(project_id, None)
            self._callbacks.pop(project_id, None)

            observer.stop()
            observer.join(timeout=2)

            logger.info(f"Stopped watching project {project_id}")

    async def add_listener(self, project_id: str, callback: Callable):
        """Add a callback listener for file changes in a project."""
        with self._lock:
            if project_id in self._callbacks:
                self._callbacks[project_id].add(callback)

    async def remove_listener(self, project_id: str, callback: Callable):
        """Remove a callback listener."""
        with self._lock:
            if project_id in self._callbacks:
                self._callbacks[project_id].discard(callback)

                # Stop watching if no more listeners
                if not self._callbacks[project_id]:
                    self._stop_watching_sync(project_id)

    def _stop_watching_sync(self, project_id: str):
        """Stop watching synchronously (internal use, must hold lock)."""
        if project_id not in self._observers:
            return

        observer = self._observers.pop(project_id)
        self._handlers.pop(project_id, None)
        self._callbacks.pop(project_id, None)

        observer.stop()
        observer.join(timeout=2)

        logger.info(f"Stopped watching project {project_id} (no listeners)")

    def _on_file_change(self, project_id: str, event_type: str, path: str):
        """Handle file change event (called from main event loop thread)."""
        with self._lock:
            callbacks = self._callbacks.get(project_id, set()).copy()

        for callback in callbacks:
            try:
                if asyncio.iscoroutinefunction(callback):
                    asyncio.create_task(callback(event_type, path))
                else:
                    callback(event_type, path)
            except Exception as e:
                logger.error(f"Error in file change callback: {e}")

    async def stop_all(self):
        """Stop all watchers."""
        with self._lock:
            for project_id in list(self._observers.keys()):
                observer = self._observers.pop(project_id)
                observer.stop()
                observer.join(timeout=2)

            self._handlers.clear()
            self._callbacks.clear()
            logger.info("Stopped all file watchers")


# Global instance
file_watcher = FileWatcherService()
