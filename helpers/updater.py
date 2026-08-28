#!/usr/bin/python3

# SPDX-FileCopyrightText: 2026 Dr. Bret Addison
# SPDX-License-Identifier: GPL-3.0-or-later

"""Release checking and verified user-level updates for Window Layouts."""

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request


CURRENT_VERSION = "1.3.1"
REPOSITORY_URL = "https://github.com/baddison2005/window-layouts-kde"
RELEASES_URL = f"{REPOSITORY_URL}/releases"
LATEST_RELEASE_API = (
    "https://api.github.com/repos/baddison2005/window-layouts-kde/releases/latest"
)
USER_AGENT = f"Window-Layouts-KDE/{CURRENT_VERSION}"
MAX_RELEASE_RESPONSE_BYTES = 2 * 1024 * 1024
MAX_ARCHIVE_BYTES = 50 * 1024 * 1024
MAX_CHECKSUM_BYTES = 16 * 1024
SEMANTIC_VERSION = re.compile(r"^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")


class UpdateError(RuntimeError):
    """A safe, user-presentable update failure."""


def version_tuple(version):
    """Parse a stable three-part semantic version."""
    match = SEMANTIC_VERSION.fullmatch(str(version).strip())
    if match is None:
        raise UpdateError(f"Unsupported release version: {version}")
    return tuple(int(part) for part in match.groups())


class UpdateManager:
    """Check GitHub Releases and install checksum-verified source packages."""

    def __init__(self, current_version=CURRENT_VERSION, urlopen=None):
        self.current_version = str(current_version)
        version_tuple(self.current_version)
        self._urlopen = urlopen or urllib.request.urlopen

    def _read_url(self, url, maximum_bytes, timeout=15):
        request = urllib.request.Request(
            url,
            headers={
                "Accept": "application/vnd.github+json",
                "User-Agent": USER_AGENT,
                "X-GitHub-Api-Version": "2022-11-28",
            },
        )
        try:
            with self._urlopen(request, timeout=timeout) as response:
                content_length = response.headers.get("Content-Length")
                if content_length and int(content_length) > maximum_bytes:
                    raise UpdateError("The update response is unexpectedly large")
                payload = response.read(maximum_bytes + 1)
        except UpdateError:
            raise
        except (OSError, ValueError, urllib.error.URLError) as error:
            raise UpdateError(f"Could not contact GitHub: {error}") from error
        if len(payload) > maximum_bytes:
            raise UpdateError("The update response is unexpectedly large")
        return payload

    @staticmethod
    def _release_asset(release, name):
        for asset in release.get("assets", []):
            if asset.get("name") == name:
                url = asset.get("browser_download_url")
                if isinstance(url, str) and url.startswith("https://github.com/"):
                    return url
        return ""

    def check(self):
        """Return normalized information about GitHub's latest stable release."""
        try:
            release = json.loads(
                self._read_url(
                    LATEST_RELEASE_API,
                    MAX_RELEASE_RESPONSE_BYTES,
                ).decode("utf-8")
            )
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise UpdateError("GitHub returned an invalid release response") from error
        if not isinstance(release, dict):
            raise UpdateError("GitHub returned an invalid release response")

        tag_name = str(release.get("tag_name", ""))
        latest_version = tag_name[1:] if tag_name.startswith("v") else tag_name
        current_tuple = version_tuple(self.current_version)
        latest_tuple = version_tuple(latest_version)
        update_available = latest_tuple > current_tuple
        archive_name = f"window-layouts-kde-v{latest_version}.tar.gz"
        checksum_name = f"{archive_name}.sha256"
        archive_url = self._release_asset(release, archive_name)
        checksum_url = self._release_asset(release, checksum_name)
        can_install = update_available and bool(archive_url and checksum_url)

        return {
            "currentVersion": self.current_version,
            "latestVersion": latest_version,
            "updateAvailable": update_available,
            "canInstall": can_install,
            "releaseName": str(release.get("name") or tag_name),
            "releaseUrl": str(release.get("html_url") or RELEASES_URL),
            "publishedAt": str(release.get("published_at") or ""),
            "archiveName": archive_name,
            "archiveUrl": archive_url,
            "checksumUrl": checksum_url,
            "installReason": "" if can_install or not update_available else (
                "This release does not provide the verified update package. "
                "Open its release page to install it manually."
            ),
        }

    def _download(self, url, destination, maximum_bytes):
        destination.write_bytes(self._read_url(url, maximum_bytes, timeout=60))

    @staticmethod
    def _expected_checksum(checksum_path, archive_name):
        try:
            line = checksum_path.read_text(encoding="utf-8").strip().splitlines()[0]
            parts = line.split()
        except (FileNotFoundError, IndexError, OSError, UnicodeDecodeError) as error:
            raise UpdateError("The release checksum file is invalid") from error
        if not parts or not re.fullmatch(r"[0-9a-fA-F]{64}", parts[0]):
            raise UpdateError("The release checksum file is invalid")
        if len(parts) > 1 and parts[-1].lstrip("*") != archive_name:
            raise UpdateError("The release checksum names a different archive")
        return parts[0].lower()

    @staticmethod
    def _safe_extract(archive_path, destination, expected_root):
        """Extract regular files/directories beneath one expected root only."""
        try:
            with tarfile.open(archive_path, "r:gz") as archive:
                members = archive.getmembers()
                for member in members:
                    member_path = PurePosixPath(member.name)
                    if (
                        member_path.is_absolute()
                        or ".." in member_path.parts
                        or not member_path.parts
                        or member_path.parts[0] != expected_root
                        or member.issym()
                        or member.islnk()
                        or member.isdev()
                        or not (member.isdir() or member.isfile())
                    ):
                        raise UpdateError("The release archive contains an unsafe path")
                # All members were constrained to ordinary files/directories
                # below expected_root above, so extraction stays safe on both
                # newer Python versions and older Plasma distributions that do
                # not yet provide tarfile's filter argument.
                archive.extractall(destination, members=members)
        except UpdateError:
            raise
        except (OSError, tarfile.TarError) as error:
            raise UpdateError(f"Could not unpack the release: {error}") from error

    def install_latest(self):
        """Download, verify, unpack, and install the latest stable release."""
        release = self.check()
        if not release["updateAvailable"]:
            return {**release, "installed": False}
        if not release["canInstall"]:
            raise UpdateError(release["installReason"])

        latest_version = release["latestVersion"]
        expected_root = f"window-layouts-kde-v{latest_version}"
        with tempfile.TemporaryDirectory(prefix="window-layouts-update-") as temporary:
            temporary_path = Path(temporary)
            archive_path = temporary_path / release["archiveName"]
            checksum_path = temporary_path / f"{release['archiveName']}.sha256"
            self._download(
                release["archiveUrl"],
                archive_path,
                MAX_ARCHIVE_BYTES,
            )
            self._download(
                release["checksumUrl"],
                checksum_path,
                MAX_CHECKSUM_BYTES,
            )

            expected_checksum = self._expected_checksum(
                checksum_path,
                release["archiveName"],
            )
            actual_checksum = hashlib.sha256(archive_path.read_bytes()).hexdigest()
            if actual_checksum != expected_checksum:
                raise UpdateError("The downloaded update failed SHA-256 verification")

            extract_directory = temporary_path / "source"
            extract_directory.mkdir()
            self._safe_extract(archive_path, extract_directory, expected_root)
            release_root = extract_directory / expected_root
            try:
                packaged_version = (release_root / "VERSION").read_text(
                    encoding="utf-8"
                ).strip()
            except OSError as error:
                raise UpdateError("The release package has no readable VERSION file") from error
            if packaged_version != latest_version:
                raise UpdateError("The release package version does not match its tag")

            installer = release_root / "install-drag-overlay.sh"
            if not installer.is_file():
                raise UpdateError("The release package has no update installer")
            environment = os.environ.copy()
            # When called by the GTK configurator, quitting that same D-Bus
            # service from its child installer would deadlock. The newly copied
            # service is picked up the next time the configurator is opened.
            environment["WINDOW_LAYOUTS_SKIP_CONFIGURATOR_RESTART"] = "true"
            try:
                completed = subprocess.run(
                    ["bash", str(installer)],
                    cwd=release_root,
                    env=environment,
                    check=True,
                    capture_output=True,
                    text=True,
                    timeout=300,
                )
            except subprocess.TimeoutExpired as error:
                raise UpdateError("The update installer timed out") from error
            except subprocess.CalledProcessError as error:
                detail = (error.stderr or error.stdout or "unknown installer error").strip()
                raise UpdateError(f"Could not install the update: {detail}") from error
            except OSError as error:
                raise UpdateError(f"Could not start the update installer: {error}") from error

        return {
            **release,
            "installed": True,
            "installerOutput": completed.stdout.strip(),
        }


def main(arguments=None):
    """Small JSON CLI used by Plasma's asynchronous executable data engine."""
    arguments = list(sys.argv[1:] if arguments is None else arguments)
    if len(arguments) != 1 or arguments[0] not in ("check", "install"):
        print(json.dumps({"error": "Usage: updater.py check|install"}))
        return 2
    manager = UpdateManager()
    try:
        result = (
            manager.check()
            if arguments[0] == "check"
            else manager.install_latest()
        )
    except UpdateError as error:
        result = {"error": str(error)}
    print(json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
