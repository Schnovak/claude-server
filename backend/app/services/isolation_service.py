"""
IsolationService: OS-level user isolation using Unix users.

This service manages Unix user creation and command execution as isolated users.
Each platform user gets their own Unix user for strong isolation.
"""
import asyncio
import logging
import os
import shutil
from pathlib import Path
from typing import List, Optional, Tuple

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..models import User

settings = get_settings()
logger = logging.getLogger(__name__)

# Check for available tools
USERADD_AVAILABLE = shutil.which("useradd") is not None
USERDEL_AVAILABLE = shutil.which("userdel") is not None
SETPRIV_AVAILABLE = shutil.which("setpriv") is not None
FIREJAIL_AVAILABLE = shutil.which("firejail") is not None
SUDO_AVAILABLE = shutil.which("sudo") is not None


class IsolationService:
    """
    Manages Unix user isolation for platform users.

    Each platform user can be assigned a dedicated Unix user, providing
    OS-level isolation between users. This is stronger than just
    filesystem sandboxing because it uses kernel-level permissions.

    Requirements:
    - Linux system with useradd/userdel
    - Sudo access for user management commands (see sudoers setup)
    - Either firejail or setpriv for running as different user
    """

    # UID range for isolated users (avoid system UIDs)
    MIN_UID = 10000
    MAX_UID = 60000

    # Username prefix for isolated users
    USERNAME_PREFIX = "claude_"

    async def check_available(self) -> dict:
        """
        Check what isolation capabilities are available.

        Returns:
            Dict with status of each capability
        """
        return {
            "unix_users": USERADD_AVAILABLE and USERDEL_AVAILABLE and SUDO_AVAILABLE,
            "setpriv": SETPRIV_AVAILABLE,
            "firejail": FIREJAIL_AVAILABLE,
            "recommended": USERADD_AVAILABLE and FIREJAIL_AVAILABLE,
        }

    async def provision_user(
        self,
        platform_user_id: str,
        db: AsyncSession
    ) -> Tuple[str, int, int]:
        """
        Provision a Unix user for a platform user.

        Creates a new Unix user with isolated home directory.
        Stores the mapping in the database.

        Args:
            platform_user_id: The platform user's ID
            db: Database session

        Returns:
            Tuple of (username, uid, gid)

        Raises:
            RuntimeError: If user creation fails
        """
        if not USERADD_AVAILABLE or not SUDO_AVAILABLE:
            raise RuntimeError("Unix user provisioning not available. Install useradd and configure sudo.")

        # Get the platform user
        result = await db.execute(select(User).where(User.id == platform_user_id))
        user = result.scalar_one_or_none()
        if not user:
            raise ValueError(f"User {platform_user_id} not found")

        # Check if already provisioned
        if user.unix_username and user.unix_uid:
            logger.info(f"User {platform_user_id} already has Unix user: {user.unix_username}")
            return user.unix_username, user.unix_uid, user.unix_gid or user.unix_uid

        # Generate username from user ID (short version)
        short_id = platform_user_id.split("-")[0]  # First segment of UUID
        username = f"{self.USERNAME_PREFIX}{short_id}"

        # Find available UID
        uid = await self._find_available_uid()
        gid = uid  # Create a group with same ID

        try:
            # Create the user with useradd
            # --system: system user (no password aging)
            # --uid: specific UID
            # --gid: specific GID (create group first)
            # --home-dir: user's workspace
            # --shell: nologin for security
            # --no-create-home: we manage the workspace separately

            workspace = settings.get_user_workspace(platform_user_id)

            # Create group first
            group_cmd = ["sudo", "groupadd", "--gid", str(gid), username]
            proc = await asyncio.create_subprocess_exec(
                *group_cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await proc.communicate()

            if proc.returncode != 0 and b"already exists" not in stderr:
                logger.warning(f"Group creation warning: {stderr.decode()}")

            # Create user
            user_cmd = [
                "sudo", "useradd",
                "--uid", str(uid),
                "--gid", str(gid),
                "--home-dir", str(workspace),
                "--shell", "/usr/sbin/nologin",
                "--no-create-home",
                username
            ]

            proc = await asyncio.create_subprocess_exec(
                *user_cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await proc.communicate()

            if proc.returncode != 0:
                error_msg = stderr.decode()
                if "already exists" in error_msg:
                    logger.info(f"Unix user {username} already exists")
                else:
                    raise RuntimeError(f"Failed to create Unix user: {error_msg}")

            # Ensure workspace exists and set ownership
            workspace.mkdir(parents=True, exist_ok=True)

            # Set ownership of workspace to the new user
            chown_cmd = ["sudo", "chown", "-R", f"{uid}:{gid}", str(workspace)]
            proc = await asyncio.create_subprocess_exec(
                *chown_cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            await proc.communicate()

            # Update database
            user.unix_username = username
            user.unix_uid = uid
            user.unix_gid = gid
            await db.commit()

            logger.info(f"Provisioned Unix user {username} (UID: {uid}) for {platform_user_id}")
            return username, uid, gid

        except Exception as e:
            logger.error(f"Failed to provision Unix user: {e}")
            raise

    async def deprovision_user(
        self,
        platform_user_id: str,
        db: AsyncSession
    ) -> bool:
        """
        Remove a Unix user for a platform user.

        Args:
            platform_user_id: The platform user's ID
            db: Database session

        Returns:
            True if successful
        """
        if not USERDEL_AVAILABLE or not SUDO_AVAILABLE:
            logger.warning("Unix user deprovisioning not available")
            return False

        # Get the platform user
        result = await db.execute(select(User).where(User.id == platform_user_id))
        user = result.scalar_one_or_none()
        if not user or not user.unix_username:
            return True  # Nothing to deprovision

        username = user.unix_username

        try:
            # Remove the user
            cmd = ["sudo", "userdel", username]
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await proc.communicate()

            if proc.returncode != 0:
                error_msg = stderr.decode()
                if "does not exist" not in error_msg:
                    logger.warning(f"Failed to remove Unix user: {error_msg}")

            # Remove the group
            cmd = ["sudo", "groupdel", username]
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            await proc.communicate()

            # Clear database fields
            user.unix_username = None
            user.unix_uid = None
            user.unix_gid = None
            await db.commit()

            logger.info(f"Deprovisioned Unix user {username}")
            return True

        except Exception as e:
            logger.error(f"Failed to deprovision Unix user: {e}")
            return False

    def build_isolated_command(
        self,
        cmd: List[str],
        uid: int,
        gid: int,
        allowed_paths: List[Path],
        readonly_paths: Optional[List[Path]] = None,
    ) -> List[str]:
        """
        Build a command that runs as a specific Unix user with sandboxing.

        This combines Unix user isolation with filesystem sandboxing for
        defense in depth.

        Args:
            cmd: The command to run
            uid: Unix UID to run as
            gid: Unix GID to run as
            allowed_paths: Paths the command can read/write
            readonly_paths: Paths the command can only read

        Returns:
            The wrapped command list
        """
        readonly_paths = readonly_paths or []

        if FIREJAIL_AVAILABLE:
            # Firejail with UID/GID - best option
            sandbox_cmd = [
                "firejail",
                "--quiet",
                "--noprofile",
                f"--force-uid={uid}",
                f"--force-gid={gid}",
                "--private-dev",
                "--private-tmp",
                "--noroot",
                "--nosound",
                "--no3d",
                "--nodvd",
                "--notv",
                "--nou2f",
                "--novideo",
            ]

            # Whitelist allowed paths
            for path in allowed_paths:
                sandbox_cmd.extend(["--whitelist", str(path)])

            # Readonly paths
            for path in readonly_paths:
                sandbox_cmd.extend(["--read-only", str(path)])

            sandbox_cmd.append("--private")
            sandbox_cmd.extend(cmd)
            return sandbox_cmd

        elif SETPRIV_AVAILABLE and SUDO_AVAILABLE:
            # setpriv via sudo - good alternative
            sandbox_cmd = [
                "sudo",
                "setpriv",
                f"--reuid={uid}",
                f"--regid={gid}",
                "--init-groups",
                "--",
            ]
            sandbox_cmd.extend(cmd)
            return sandbox_cmd

        else:
            # No isolation available - just run the command
            logger.warning(
                "SECURITY WARNING: No isolation tools available! "
                "Install firejail for proper isolation."
            )
            return cmd

    async def ensure_user_provisioned(
        self,
        platform_user_id: str,
        db: AsyncSession
    ) -> Optional[Tuple[str, int, int]]:
        """
        Ensure a platform user has a provisioned Unix user.

        Creates one if it doesn't exist.

        Args:
            platform_user_id: The platform user's ID
            db: Database session

        Returns:
            Tuple of (username, uid, gid) or None if provisioning unavailable
        """
        # Get the platform user
        result = await db.execute(select(User).where(User.id == platform_user_id))
        user = result.scalar_one_or_none()
        if not user:
            return None

        # Return existing if available
        if user.unix_username and user.unix_uid:
            return user.unix_username, user.unix_uid, user.unix_gid or user.unix_uid

        # Check if provisioning is available
        capabilities = await self.check_available()
        if not capabilities["unix_users"]:
            logger.debug("Unix user provisioning not available")
            return None

        # Provision new user
        try:
            return await self.provision_user(platform_user_id, db)
        except Exception as e:
            logger.warning(f"Could not provision Unix user: {e}")
            return None

    async def _find_available_uid(self) -> int:
        """Find an available UID in our range."""
        # Check /etc/passwd for used UIDs
        used_uids = set()

        try:
            with open("/etc/passwd", "r") as f:
                for line in f:
                    parts = line.strip().split(":")
                    if len(parts) >= 3:
                        try:
                            uid = int(parts[2])
                            if self.MIN_UID <= uid <= self.MAX_UID:
                                used_uids.add(uid)
                        except ValueError:
                            pass
        except Exception as e:
            logger.warning(f"Could not read /etc/passwd: {e}")

        # Find first available UID
        for uid in range(self.MIN_UID, self.MAX_UID):
            if uid not in used_uids:
                return uid

        raise RuntimeError("No available UIDs in range")


# Global instance
isolation_service = IsolationService()
