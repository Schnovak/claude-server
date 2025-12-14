import asyncio
import os
import signal
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, Any
import logging

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..database import get_db_context
from ..models import Job, Project
from ..models.job import JobStatus, JobType
from .artifact_scanner import artifact_scanner

settings = get_settings()
logger = logging.getLogger(__name__)


class JobRunner:
    """Background job runner for builds, tests, and dev servers."""

    def __init__(self):
        self._running = False
        self._processes: Dict[str, asyncio.subprocess.Process] = {}

    async def start(self):
        """Start the job runner loop."""
        self._running = True
        logger.info("Job runner started")
        while self._running:
            try:
                await self._process_queued_jobs()
            except Exception as e:
                logger.error(f"Error in job runner: {e}")
            await asyncio.sleep(2)  # Poll every 2 seconds

    async def stop(self):
        """Stop the job runner."""
        self._running = False
        # Cancel all running processes
        for job_id, process in self._processes.items():
            try:
                process.terminate()
            except Exception:
                pass
        logger.info("Job runner stopped")

    async def _process_queued_jobs(self):
        """Find and process queued jobs."""
        async with get_db_context() as db:
            result = await db.execute(
                select(Job).where(Job.status == JobStatus.QUEUED).limit(5)
            )
            jobs = result.scalars().all()

            for job in jobs:
                # Start job in background
                asyncio.create_task(self._run_job(job.id))

    async def _run_job(self, job_id: str):
        """Execute a single job."""
        async with get_db_context() as db:
            result = await db.execute(select(Job).where(Job.id == job_id))
            job = result.scalar_one_or_none()
            if not job:
                return

            # Get project
            result = await db.execute(
                select(Project).where(Project.id == job.project_id)
            )
            project = result.scalar_one_or_none()
            if not project:
                await self._fail_job(db, job, "Project not found")
                return

            # Update job status
            job.status = JobStatus.RUNNING
            job.started_at = datetime.utcnow()
            job.log_path = str(settings.job_logs_path / f"{job_id}.log")
            await db.commit()

            # Build command based on job type
            try:
                cmd, env = self._build_command(job, project)
            except ValueError as e:
                await self._fail_job(db, job, str(e))
                return

            # Ensure log directory exists
            settings.job_logs_path.mkdir(parents=True, exist_ok=True)

            # Run the command
            try:
                with open(job.log_path, "w") as log_file:
                    process = await asyncio.create_subprocess_shell(
                        cmd,
                        stdout=log_file,
                        stderr=asyncio.subprocess.STDOUT,
                        cwd=project.root_path,
                        env={**os.environ, **env},
                    )
                    self._processes[job_id] = process
                    job.pid = process.pid
                    await db.commit()

                    return_code = await process.wait()

                    del self._processes[job_id]

                    if return_code == 0:
                        job.status = JobStatus.SUCCESS
                        # Scan for build artifacts
                        if job.type in [JobType.BUILD_APK, JobType.BUILD_WEB]:
                            try:
                                artifacts = await artifact_scanner.scan_and_create(
                                    job, project, db
                                )
                                logger.info(
                                    f"Created {len(artifacts)} artifacts for job {job.id}"
                                )
                            except Exception as e:
                                logger.error(f"Failed to scan artifacts: {e}")
                    else:
                        job.status = JobStatus.FAILED

                    job.finished_at = datetime.utcnow()
                    job.pid = None
                    await db.commit()

            except Exception as e:
                logger.error(f"Job {job_id} failed: {e}")
                await self._fail_job(db, job, str(e))

    def _build_command(self, job: Job, project: Project) -> tuple[str, dict]:
        """Build the command and environment for a job."""
        env = {}
        scripts_path = Path(__file__).parent.parent.parent / "scripts"

        if job.type == JobType.BUILD_APK:
            cmd = f"bash {scripts_path}/build_flutter_apk.sh"

        elif job.type == JobType.BUILD_WEB:
            cmd = f"bash {scripts_path}/build_flutter_web.sh"

        elif job.type == JobType.TEST:
            # Detect project type and run appropriate tests
            if project.type.value == "flutter":
                cmd = "flutter test"
            elif project.type.value == "node":
                cmd = "npm test"
            elif project.type.value == "python":
                cmd = "pytest"
            else:
                cmd = "echo 'No test command configured'"

        elif job.type == JobType.DEV_SERVER:
            # Get port from metadata or use default
            port = (job.metadata_json or {}).get("port", 8080)
            if project.type.value == "flutter":
                cmd = f"flutter run -d web-server --web-port={port}"
            elif project.type.value == "node":
                cmd = f"PORT={port} npm start"
            else:
                raise ValueError(f"Dev server not supported for {project.type.value}")
            env["PORT"] = str(port)

        elif job.type == JobType.CUSTOM_COMMAND:
            if not job.command:
                raise ValueError("Custom command not specified")
            # Sanitize: only allow certain commands
            cmd = self._sanitize_command(job.command)

        else:
            raise ValueError(f"Unknown job type: {job.type}")

        return cmd, env

    def _sanitize_command(self, command: str) -> str:
        """
        Sanitize custom commands.
        Only allow safe commands, no shell operators.
        """
        # Block dangerous patterns
        dangerous = [";", "&&", "||", "|", ">", "<", "`", "$(",
                     "rm -rf", "sudo", "chmod", "chown"]
        for pattern in dangerous:
            if pattern in command:
                raise ValueError(f"Dangerous pattern in command: {pattern}")
        return command

    async def _fail_job(self, db: AsyncSession, job: Job, error: str):
        """Mark a job as failed."""
        job.status = JobStatus.FAILED
        job.finished_at = datetime.utcnow()
        if job.log_path:
            try:
                with open(job.log_path, "a") as f:
                    f.write(f"\n\nERROR: {error}\n")
            except Exception:
                pass
        await db.commit()

    async def cancel_job(self, job_id: str) -> bool:
        """Cancel a running job."""
        if job_id in self._processes:
            process = self._processes[job_id]
            try:
                process.terminate()
                await asyncio.sleep(0.5)
                if process.returncode is None:
                    process.kill()
                return True
            except Exception as e:
                logger.error(f"Failed to cancel job {job_id}: {e}")
                return False

        # Update DB status
        async with get_db_context() as db:
            result = await db.execute(select(Job).where(Job.id == job_id))
            job = result.scalar_one_or_none()
            if job and job.status in [JobStatus.QUEUED, JobStatus.RUNNING]:
                job.status = JobStatus.CANCELLED
                job.finished_at = datetime.utcnow()
                await db.commit()
                return True
        return False


# Global job runner instance
job_runner = JobRunner()
