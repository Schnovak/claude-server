from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File, Query
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List, Optional
from pathlib import Path
import aiofiles
import os
import shutil

from ..database import get_db
from ..models import User, Project, Artifact
from ..models.artifact import ArtifactKind as ArtifactKindModel
from ..schemas import ArtifactResponse
from ..services.auth import get_current_user
from ..services.workspace import WorkspaceService
from ..config import get_settings

router = APIRouter(tags=["files"])
settings = get_settings()


# ============== Project Files ==============

@router.post("/projects/{project_id}/files/upload")
async def upload_file(
    project_id: str,
    file: UploadFile = File(...),
    path: str = Query("", description="Relative path within project"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Upload a file to a project."""
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

    # Build destination path
    dest_dir = Path(project.root_path) / path
    dest_path = dest_dir / file.filename

    # Security check
    if not WorkspaceService.validate_path_within_workspace(
        current_user.id, dest_path
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid path"
        )

    # Create directory if needed
    dest_dir.mkdir(parents=True, exist_ok=True)

    # Save file
    async with aiofiles.open(dest_path, "wb") as f:
        content = await file.read()
        await f.write(content)

    return {
        "message": "File uploaded",
        "path": str(dest_path.relative_to(project.root_path)),
        "size": len(content)
    }


@router.get("/projects/{project_id}/files/download")
async def download_file(
    project_id: str,
    path: str = Query(..., description="Relative path within project"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Download a file from a project."""
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

    # Build file path
    file_path = Path(project.root_path) / path

    # Security check
    if not WorkspaceService.validate_path_within_workspace(
        current_user.id, file_path
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid path"
        )

    if not file_path.exists():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="File not found"
        )

    return FileResponse(
        path=str(file_path),
        filename=file_path.name,
    )


@router.get("/projects/{project_id}/files/list")
async def list_files(
    project_id: str,
    path: str = Query("", description="Relative path within project"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """List files in a project directory."""
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

    # Build directory path
    dir_path = Path(project.root_path) / path

    # Security check
    if not WorkspaceService.validate_path_within_workspace(
        current_user.id, dir_path
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid path"
        )

    if not dir_path.exists():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Directory not found"
        )

    items = []
    for item in dir_path.iterdir():
        items.append({
            "name": item.name,
            "is_dir": item.is_dir(),
            "size": item.stat().st_size if item.is_file() else None,
            "modified": item.stat().st_mtime,
        })

    return {"items": sorted(items, key=lambda x: (not x["is_dir"], x["name"]))}


@router.delete("/projects/{project_id}/files")
async def delete_file(
    project_id: str,
    path: str = Query(..., description="Relative path within project"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Delete a file or directory from a project."""
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

    # Build file path
    file_path = Path(project.root_path) / path

    # Security check
    if not WorkspaceService.validate_path_within_workspace(
        current_user.id, file_path
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid path"
        )

    if not file_path.exists():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="File not found"
        )

    if file_path.is_dir():
        shutil.rmtree(file_path)
    else:
        file_path.unlink()

    return {"message": "Deleted"}


# ============== Artifacts ==============

@router.get("/projects/{project_id}/artifacts", response_model=List[ArtifactResponse])
async def list_artifacts(
    project_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """List artifacts for a project."""
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
        select(Artifact).where(Artifact.project_id == project_id)
        .order_by(Artifact.created_at.desc())
    )
    artifacts = result.scalars().all()

    return [ArtifactResponse.model_validate(a) for a in artifacts]


@router.get("/artifacts/{artifact_id}/download")
async def download_artifact(
    artifact_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Download an artifact."""
    result = await db.execute(
        select(Artifact).where(
            Artifact.id == artifact_id,
            Artifact.owner_id == current_user.id
        )
    )
    artifact = result.scalar_one_or_none()

    if not artifact:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Artifact not found"
        )

    if not Path(artifact.file_path).exists():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Artifact file not found"
        )

    return FileResponse(
        path=artifact.file_path,
        filename=Path(artifact.file_path).name,
    )


@router.delete("/artifacts/{artifact_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_artifact(
    artifact_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Delete an artifact."""
    result = await db.execute(
        select(Artifact).where(
            Artifact.id == artifact_id,
            Artifact.owner_id == current_user.id
        )
    )
    artifact = result.scalar_one_or_none()

    if not artifact:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Artifact not found"
        )

    # Delete file if exists
    if Path(artifact.file_path).exists():
        Path(artifact.file_path).unlink()

    await db.delete(artifact)
    await db.commit()
