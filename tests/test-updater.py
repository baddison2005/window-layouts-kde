#!/usr/bin/python3

# SPDX-License-Identifier: GPL-3.0-or-later

"""Offline regression checks for the GitHub release updater."""

import io
import hashlib
import json
from pathlib import Path
import sys
import tarfile
import tempfile


PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "helpers"))

from updater import UpdateError, UpdateManager, version_tuple  # noqa: E402


class FakeResponse:
    def __init__(self, payload):
        self.payload = payload
        self.headers = {"Content-Length": str(len(payload))}

    def __enter__(self):
        return self

    def __exit__(self, _type, _value, _traceback):
        return False

    def read(self, maximum_bytes):
        return self.payload[:maximum_bytes]


def fake_release_opener(release):
    payload = json.dumps(release).encode("utf-8")

    def open_release(_request, timeout=0):
        assert timeout > 0
        return FakeResponse(payload)

    return open_release


assert version_tuple("v1.2.0") == (1, 2, 0)
try:
    version_tuple("1.2")
except UpdateError:
    pass
else:
    raise AssertionError("Incomplete semantic versions must be rejected")

archive_name = "window-layouts-kde-v1.3.0.tar.gz"
release = {
    "tag_name": "v1.3.0",
    "name": "Window Layouts 1.3.0",
    "html_url": "https://github.com/baddison2005/window-layouts-kde/releases/tag/v1.3.0",
    "assets": [
        {
            "name": archive_name,
            "browser_download_url": (
                "https://github.com/baddison2005/window-layouts-kde/releases/"
                f"download/v1.3.0/{archive_name}"
            ),
        },
        {
            "name": f"{archive_name}.sha256",
            "browser_download_url": (
                "https://github.com/baddison2005/window-layouts-kde/releases/"
                f"download/v1.3.0/{archive_name}.sha256"
            ),
        },
    ],
}
available = UpdateManager(
    current_version="1.2.0",
    urlopen=fake_release_opener(release),
).check()
assert available["updateAvailable"]
assert available["canInstall"]
assert available["latestVersion"] == "1.3.0"

current = UpdateManager(
    current_version="1.3.0",
    urlopen=fake_release_opener(release),
).check()
assert not current["updateAvailable"]
assert not current["canInstall"]

with tempfile.TemporaryDirectory() as temporary:
    temporary_path = Path(temporary)
    archive_path = temporary_path / "unsafe.tar.gz"
    with tarfile.open(archive_path, "w:gz") as archive:
        payload = b"unsafe"
        member = tarfile.TarInfo("../outside")
        member.size = len(payload)
        archive.addfile(member, io.BytesIO(payload))
    try:
        UpdateManager._safe_extract(
            archive_path,
            temporary_path / "extract",
            "window-layouts-kde-v1.3.0",
        )
    except UpdateError:
        pass
    else:
        raise AssertionError("Path traversal in an update archive must be rejected")

with tempfile.TemporaryDirectory() as temporary:
    temporary_path = Path(temporary)
    archive_path = temporary_path / archive_name
    checksum_path = temporary_path / f"{archive_name}.sha256"
    with tarfile.open(archive_path, "w:gz") as archive:
        for relative_name, payload in (
            ("VERSION", b"1.3.0\n"),
            (
                "install-drag-overlay.sh",
                b"#!/usr/bin/env bash\nset -eu\nprintf 'offline installer ran\\n'\n",
            ),
        ):
            member = tarfile.TarInfo(
                f"window-layouts-kde-v1.3.0/{relative_name}"
            )
            member.mode = 0o755 if relative_name.endswith(".sh") else 0o644
            member.size = len(payload)
            archive.addfile(member, io.BytesIO(payload))
    digest = hashlib.sha256(archive_path.read_bytes()).hexdigest()
    checksum_path.write_text(
        f"{digest}  {archive_name}\n",
        encoding="utf-8",
    )

    class OfflineInstallManager(UpdateManager):
        def check(self):
            return {
                **available,
                "archiveUrl": "archive",
                "checksumUrl": "checksum",
            }

        def _download(self, url, destination, _maximum_bytes):
            source = archive_path if url == "archive" else checksum_path
            destination.write_bytes(source.read_bytes())

    installed = OfflineInstallManager(current_version="1.2.0").install_latest()
    assert installed["installed"]
    assert installed["latestVersion"] == "1.3.0"
    assert installed["installerOutput"] == "offline installer ran"

print("Updater checks passed")
