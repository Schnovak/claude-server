from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List

from ..database import get_db
from ..models import User, Project
from ..models.project import ProjectType as ProjectTypeModel
from ..schemas import ProjectCreate, ProjectResponse
from ..services.auth import get_current_user
from ..services.workspace import WorkspaceService
from ..config import get_settings

router = APIRouter(prefix="/projects", tags=["projects"])
settings = get_settings()


@router.get("", response_model=List[ProjectResponse])
async def list_projects(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """List all projects for the current user."""
    result = await db.execute(
        select(Project).where(Project.owner_id == current_user.id)
    )
    projects = result.scalars().all()
    return [ProjectResponse.model_validate(p) for p in projects]


@router.post("", response_model=ProjectResponse, status_code=status.HTTP_201_CREATED)
async def create_project(
    project_data: ProjectCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Create a new project."""
    # Create project record
    project = Project(
        owner_id=current_user.id,
        name=project_data.name,
        type=ProjectTypeModel(project_data.type.value),
        root_path="",  # Will be set after we have the ID
    )
    db.add(project)
    await db.flush()  # Get the project ID

    # Create project directory
    project_path = await WorkspaceService.create_project_directory(
        current_user.id, project.id
    )

    # Update root_path
    project.root_path = str(project_path)

    await db.commit()
    await db.refresh(project)

    return ProjectResponse.model_validate(project)


@router.get("/{project_id}", response_model=ProjectResponse)
async def get_project(
    project_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get a specific project."""
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

    return ProjectResponse.model_validate(project)


@router.delete("/{project_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_project(
    project_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Delete a project and its files."""
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

    # Delete project directory
    await WorkspaceService.delete_project_directory(current_user.id, project_id)

    # Delete from database (cascades to jobs and artifacts)
    await db.delete(project)
    await db.commit()
