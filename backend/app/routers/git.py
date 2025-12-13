from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from typing import Optional, List
from pathlib import Path
import asyncio

from ..database import get_db
from ..models import User, Project
from ..services.auth import get_current_user
from ..services.workspace import WorkspaceService
from ..config import get_settings

router = APIRouter(tags=["git"])
settings = get_settings()


class GitInitRequest(BaseModel):
    default_branch: str = "main"


class GitCommitRequest(BaseModel):
    message: str
    push: bool = True


class GitRemoteRequest(BaseModel):
    url: str
    name: str = "origin"


class GitFileStatus(BaseModel):
    path: str
    status: str  # M, A, D, ??, etc.


class GitStatusResponse(BaseModel):
    branch: str
    files: List[GitFileStatus]
    ahead: int = 0
    behind: int = 0
    remote_url: Optional[str] = None
    remote_web_url: Optional[str] = None  # Browser-friendly URL


async def run_git_command(cwd: Path, *args) -> tuple[int, str, str]:
    """Run a git command and return (returncode, stdout, stderr)."""
    process = await asyncio.create_subprocess_exec(
        "git", *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        cwd=str(cwd)
    )
    stdout, stderr = await process.communicate()
    return process.returncode, stdout.decode(), stderr.decode()


def git_url_to_web_url(git_url: str) -> Optional[str]:
    """Convert a git remote URL to a browser-friendly web URL."""
    import re

    if not git_url:
        return None

    git_url = git_url.strip()

    # SSH format: git@github.com:user/repo.git
    ssh_match = re.match(r'git@([^:]+):(.+?)(?:\.git)?$', git_url)
    if ssh_match:
        host, path = ssh_match.groups()
        return f"https://{host}/{path}"

    # HTTPS format: https://github.com/user/repo.git
    https_match = re.match(r'https?://([^/]+)/(.+?)(?:\.git)?$', git_url)
    if https_match:
        host, path = https_match.groups()
        return f"https://{host}/{path}"

    # Already a web URL or unknown format
    if git_url.startswith('http'):
        return git_url.rstrip('.git')

    return None


@router.post("/projects/{project_id}/git/init")
async def git_init(
    project_id: str,
    request: GitInitRequest = GitInitRequest(),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Initialize a git repository in the project."""
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

    project_path = Path(project.root_path)

    # Check if already a git repo
    if (project_path / ".git").exists():
        return {"message": "Git repository already initialized"}

    # Init
    code, stdout, stderr = await run_git_command(
        project_path, "init", "-b", request.default_branch
    )
    if code != 0:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Git init failed: {stderr}"
        )

    return {"message": "Git repository initialized", "branch": request.default_branch}


@router.get("/projects/{project_id}/git/status", response_model=GitStatusResponse)
async def git_status(
    project_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get git status for a project."""
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

    project_path = Path(project.root_path)

    if not (project_path / ".git").exists():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Not a git repository"
        )

    # Get current branch
    code, branch, _ = await run_git_command(
        project_path, "rev-parse", "--abbrev-ref", "HEAD"
    )
    branch = branch.strip() if code == 0 else "unknown"

    # Get status
    code, stdout, _ = await run_git_command(
        project_path, "status", "--porcelain"
    )

    files = []
    if stdout:
        for line in stdout.strip().split("\n"):
            if line:
                status_code = line[:2].strip()
                file_path = line[3:]
                files.append(GitFileStatus(path=file_path, status=status_code))

    # Get ahead/behind (if remote exists)
    ahead = 0
    behind = 0
    code, rev_list, _ = await run_git_command(
        project_path, "rev-list", "--left-right", "--count", f"{branch}...origin/{branch}"
    )
    if code == 0 and rev_list.strip():
        parts = rev_list.strip().split()
        if len(parts) == 2:
            ahead = int(parts[0])
            behind = int(parts[1])

    # Get remote URL
    remote_url = None
    remote_web_url = None
    code, remote_out, _ = await run_git_command(
        project_path, "remote", "get-url", "origin"
    )
    if code == 0 and remote_out.strip():
        remote_url = remote_out.strip()
        remote_web_url = git_url_to_web_url(remote_url)

    return GitStatusResponse(
        branch=branch,
        files=files,
        ahead=ahead,
        behind=behind,
        remote_url=remote_url,
        remote_web_url=remote_web_url,
    )


@router.post("/projects/{project_id}/git/commit-and-push")
async def git_commit_and_push(
    project_id: str,
    request: GitCommitRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Stage all changes, commit, and optionally push."""
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

    project_path = Path(project.root_path)

    if not (project_path / ".git").exists():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Not a git repository"
        )

    # Stage all changes
    code, _, stderr = await run_git_command(project_path, "add", "-A")
    if code != 0:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Git add failed: {stderr}"
        )

    # Commit
    code, stdout, stderr = await run_git_command(
        project_path, "commit", "-m", request.message
    )
    if code != 0:
        if "nothing to commit" in stderr or "nothing to commit" in stdout:
            return {"message": "Nothing to commit"}
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Git commit failed: {stderr}"
        )

    result_msg = "Changes committed"

    # Push if requested
    if request.push:
        code, _, stderr = await run_git_command(project_path, "push")
        if code != 0:
            # Try setting upstream
            code2, branch, _ = await run_git_command(
                project_path, "rev-parse", "--abbrev-ref", "HEAD"
            )
            branch = branch.strip()
            code, _, stderr = await run_git_command(
                project_path, "push", "-u", "origin", branch
            )
            if code != 0:
                return {
                    "message": "Committed but push failed",
                    "error": stderr,
                    "pushed": False
                }
        result_msg = "Changes committed and pushed"

    return {"message": result_msg, "pushed": request.push}


@router.post("/projects/{project_id}/git/remote")
async def set_git_remote(
    project_id: str,
    request: GitRemoteRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Set or update a git remote."""
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

    project_path = Path(project.root_path)

    if not (project_path / ".git").exists():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Not a git repository"
        )

    # Try to add remote, if fails try to set-url
    code, _, stderr = await run_git_command(
        project_path, "remote", "add", request.name, request.url
    )
    if code != 0:
        code, _, stderr = await run_git_command(
            project_path, "remote", "set-url", request.name, request.url
        )
        if code != 0:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to set remote: {stderr}"
            )

    return {"message": f"Remote '{request.name}' set to {request.url}"}


@router.get("/projects/{project_id}/git/log")
async def git_log(
    project_id: str,
    limit: int = 10,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get recent git commits."""
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

    project_path = Path(project.root_path)

    if not (project_path / ".git").exists():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Not a git repository"
        )

    code, stdout, _ = await run_git_command(
        project_path, "log", f"-{limit}",
        "--pretty=format:%H|%an|%ae|%at|%s"
    )

    commits = []
    if code == 0 and stdout:
        for line in stdout.strip().split("\n"):
            parts = line.split("|", 4)
            if len(parts) == 5:
                commits.append({
                    "hash": parts[0],
                    "author": parts[1],
                    "email": parts[2],
                    "timestamp": int(parts[3]),
                    "message": parts[4]
                })

    return {"commits": commits}
