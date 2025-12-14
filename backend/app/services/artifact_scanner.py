"""
ArtifactScanner: Automatically finds and registers build outputs as artifacts.
"""
import asyncio
import logging
import shutil
import uuid
import zipfile
from datetime import datetime
from pathlib import Path
from typing import List, Optional, Tuple

from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..models import Artifact, Job, Project
from ..models.artifact import ArtifactKind
from ..models.job import JobType

settings = get_settings()
logger = logging.getLogger(__name__)


class ArtifactScanner:
    """Scans for build outputs and creates artifact records."""

    # Mapping of job types to expected build outputs
    # Each entry is (relative_path, artifact_kind, label)
    BUILD_OUTPUTS: dict[JobType, List[Tuple[str, ArtifactKind, str]]] = {
        JobType.BUILD_APK: [
            ("build/app/outputs/flutter-apk/app-release.apk", ArtifactKind.APK, "Release APK"),
            ("build/app/outputs/flutter-apk/app-debug.apk", ArtifactKind.APK, "Debug APK"),
            ("build/app/outputs/bundle/release/app-release.aab", ArtifactKind.AAB, "Release App Bundle"),
        ],
        JobType.BUILD_WEB: [
            ("build/web", ArtifactKind.WEB_BUILD, "Web Build"),
        ],
    }

    async def scan_and_create(
        self,
        job: Job,
        project: Project,
        db: AsyncSession
    ) -> List[Artifact]:
        """
        Scan for build outputs and create artifact records.

        Args:
            job: The completed job
            project: The project that was built
            db: Database session

        Returns:
            List of created artifacts
        """
        if job.type not in self.BUILD_OUTPUTS:
            logger.debug(f"Job type {job.type} has no build outputs configured")
            return []

        outputs = self.BUILD_OUTPUTS[job.type]
        project_path = Path(project.root_path)
        created_artifacts = []

        for relative_path, kind, label in outputs:
            source_path = project_path / relative_path

            if not source_path.exists():
                logger.debug(f"Build output not found: {source_path}")
                continue

            try:
                artifact = await self._create_artifact(
                    source_path=source_path,
                    kind=kind,
                    label=label,
                    job=job,
                    project=project,
                    db=db
                )
                if artifact:
                    created_artifacts.append(artifact)
                    logger.info(f"Created artifact: {artifact.label} ({artifact.kind.value})")

            except Exception as e:
                logger.error(f"Failed to create artifact from {source_path}: {e}")

        return created_artifacts

    async def _create_artifact(
        self,
        source_path: Path,
        kind: ArtifactKind,
        label: str,
        job: Job,
        project: Project,
        db: AsyncSession
    ) -> Optional[Artifact]:
        """
        Create a single artifact record and copy to storage.

        For directories (like web builds), creates a zip first.
        """
        artifact_id = str(uuid.uuid4())
        user_artifacts_path = settings.get_user_artifacts_path(project.owner_id)
        user_artifacts_path.mkdir(parents=True, exist_ok=True)

        # Handle directories by zipping them
        if source_path.is_dir():
            dest_filename = f"{artifact_id}.zip"
            dest_path = user_artifacts_path / dest_filename
            file_size = await self._zip_directory(source_path, dest_path)
        else:
            # Copy file to artifacts directory
            dest_filename = f"{artifact_id}_{source_path.name}"
            dest_path = user_artifacts_path / dest_filename
            file_size = await self._copy_file(source_path, dest_path)

        if file_size is None:
            return None

        # Create artifact record
        artifact = Artifact(
            id=artifact_id,
            project_id=project.id,
            owner_id=project.owner_id,
            job_id=job.id,
            file_path=str(dest_path),
            kind=kind,
            label=label,
            file_size=file_size,
            created_at=datetime.utcnow()
        )

        db.add(artifact)
        await db.commit()
        await db.refresh(artifact)

        return artifact

    async def _zip_directory(self, source_dir: Path, dest_zip: Path) -> Optional[int]:
        """
        Zip a directory and return the file size.

        Runs in a thread to avoid blocking.
        """
        def _do_zip():
            try:
                with zipfile.ZipFile(dest_zip, 'w', zipfile.ZIP_DEFLATED) as zf:
                    for file_path in source_dir.rglob('*'):
                        if file_path.is_file():
                            arcname = file_path.relative_to(source_dir)
                            zf.write(file_path, arcname)
                return dest_zip.stat().st_size
            except Exception as e:
                logger.error(f"Failed to zip directory {source_dir}: {e}")
                return None

        return await asyncio.to_thread(_do_zip)

    async def _copy_file(self, source: Path, dest: Path) -> Optional[int]:
        """
        Copy a file and return its size.

        Runs in a thread to avoid blocking.
        """
        def _do_copy():
            try:
                shutil.copy2(source, dest)
                return dest.stat().st_size
            except Exception as e:
                logger.error(f"Failed to copy file {source}: {e}")
                return None

        return await asyncio.to_thread(_do_copy)


# Global scanner instance
artifact_scanner = ArtifactScanner()
