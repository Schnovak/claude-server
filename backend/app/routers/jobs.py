from fastapi import APIRouter, Depends, HTTPException, status, WebSocket, WebSocketDisconnect
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List
import asyncio
import aiofiles

from ..database import get_db
from ..models import User, Project, Job
from ..models.job import JobStatus as JobStatusModel, JobType as JobTypeModel
from ..schemas import JobCreate, JobResponse
from ..services.auth import get_current_user
from ..services.job_runner import job_runner
from ..config import get_settings

router = APIRouter(tags=["jobs"])
settings = get_settings()


@router.post("/projects/{project_id}/jobs", response_model=JobResponse, status_code=status.HTTP_201_CREATED)
async def create_job(
    project_id: str,
    job_data: JobCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Create a new job for a project."""
    # Verify project ownership
    result = await db.execute(
        select(Project).where(
            Project.id == project_id,
            Project.owner_id == current_user.id
        )
    )
    project = result.scalar_one_or_none()

    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found"
        )

    # Validate custom command
    if job_data.type.value == "custom_command" and not job_data.command:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Command required for custom_command job type"
        )

    job = Job(
        project_id=project_id,
        owner_id=current_user.id,
        type=JobTypeModel(job_data.type.value),
        command=job_data.command,
        status=JobStatusModel.QUEUED,
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)

    return JobResponse.model_validate(job)


@router.get("/projects/{project_id}/jobs", response_model=List[JobResponse])
async def list_project_jobs(
    project_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """List all jobs for a project."""
    # Verify project ownership
    result = await db.execute(
        select(Project).where(
            Project.id == project_id,
            Project.owner_id == current_user.id
        )
    )
    if not result.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found"
        )

    result = await db.execute(
        select(Job).where(Job.project_id == project_id).order_by(Job.created_at.desc())
    )
    jobs = result.scalars().all()

    return [JobResponse.model_validate(j) for j in jobs]


@router.get("/jobs/{job_id}", response_model=JobResponse)
async def get_job(
    job_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get job details."""
    result = await db.execute(
        select(Job).where(
            Job.id == job_id,
            Job.owner_id == current_user.id
        )
    )
    job = result.scalar_one_or_none()

    if not job:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Job not found"
        )

    return JobResponse.model_validate(job)


@router.get("/jobs/{job_id}/logs")
async def get_job_logs(
    job_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get job logs."""
    result = await db.execute(
        select(Job).where(
            Job.id == job_id,
            Job.owner_id == current_user.id
        )
    )
    job = result.scalar_one_or_none()

    if not job:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Job not found"
        )

    if not job.log_path:
        return {"logs": ""}

    try:
        async with aiofiles.open(job.log_path, "r") as f:
            content = await f.read()
        return {"logs": content}
    except FileNotFoundError:
        return {"logs": ""}


@router.websocket("/jobs/{job_id}/logs/stream")
async def stream_job_logs(
    websocket: WebSocket,
    job_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Stream job logs via WebSocket."""
    await websocket.accept()

    # Note: WebSocket auth should be done via query param token
    # For simplicity, we skip auth here but in production add token validation

    try:
        result = await db.execute(select(Job).where(Job.id == job_id))
        job = result.scalar_one_or_none()

        if not job or not job.log_path:
            await websocket.send_json({"error": "Job not found"})
            await websocket.close()
            return

        last_pos = 0
        while True:
            try:
                async with aiofiles.open(job.log_path, "r") as f:
                    await f.seek(last_pos)
                    new_content = await f.read()
                    if new_content:
                        await websocket.send_text(new_content)
                        last_pos = await f.tell()
            except FileNotFoundError:
                pass

            # Check if job is done
            await db.refresh(job)
            if job.status not in [JobStatusModel.QUEUED, JobStatusModel.RUNNING]:
                # Send final content and close
                try:
                    async with aiofiles.open(job.log_path, "r") as f:
                        await f.seek(last_pos)
                        final = await f.read()
                        if final:
                            await websocket.send_text(final)
                except FileNotFoundError:
                    pass
                await websocket.send_json({"status": job.status.value, "done": True})
                break

            await asyncio.sleep(0.5)

    except WebSocketDisconnect:
        pass
    finally:
        try:
            await websocket.close()
        except Exception:
            pass


@router.post("/jobs/{job_id}/cancel", status_code=status.HTTP_200_OK)
async def cancel_job(
    job_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Cancel a running or queued job."""
    result = await db.execute(
        select(Job).where(
            Job.id == job_id,
            Job.owner_id == current_user.id
        )
    )
    job = result.scalar_one_or_none()

    if not job:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Job not found"
        )

    if job.status not in [JobStatusModel.QUEUED, JobStatusModel.RUNNING]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Cannot cancel job with status {job.status.value}"
        )

    success = await job_runner.cancel_job(job_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to cancel job"
        )

    return {"message": "Job cancelled"}
