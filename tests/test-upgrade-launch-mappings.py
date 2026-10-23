#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise upgrade installation with isolated settings and fake desktop services."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

PROJECT = Path(__file__).resolve().parents[1]
CURRENT_VERSION = (PROJECT / "VERSION").read_text().strip()
STUB = '''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["WL_TEST_LOG"], "a") as log:
    log.write(json.dumps([name, *args]) + "\\n")
if name == "qtpaths6":
    print(os.environ["XDG_DATA_HOME"] if "GenericDataLocation" in args else os.environ["XDG_CONFIG_HOME"])
elif name == "kpackagetool6":
    sys.exit(1 if "--show" in args else 0)
elif name == "qdbus-qt6":
    if os.environ.get("WL_TEST_FAIL") and "reconfigure" in args:
        sys.exit(1)
    print(0)
'''


def scenario(previous_version, skip, fail=False):
    with tempfile.TemporaryDirectory(prefix="window-layouts-upgrade-test-") as directory:
        root = Path(directory)
        commands = root / "bin"
        commands.mkdir()
        for name in ("qtpaths6", "kpackagetool6", "qdbus-qt6", "systemd-run", "systemctl"):
            path = commands / name
            path.write_text(STUB)
            path.chmod(0o755)
        env = dict(os.environ, PATH=f"{commands}:{os.environ['PATH']}",
                   XDG_DATA_HOME=str(root / "data"), XDG_CONFIG_HOME=str(root / "config"),
                   XDG_CACHE_HOME=str(root / "cache"), WL_TEST_LOG=str(root / "calls.jsonl"),
                   WINDOW_LAYOUTS_SKIP_CONFIGURATOR_RESTART="true" if skip else "false")
        if fail:
            env["WL_TEST_FAIL"] = "1"
        Path(env["XDG_CONFIG_HOME"]).mkdir()
        installed = Path(env["XDG_DATA_HOME"]) / "window-layouts-kde/configurator"
        installed.mkdir(parents=True)
        (installed / "window-layouts-configurator-service").write_text("old service")
        (installed / "VERSION").write_text(previous_version + "\n")
        mappings = json.dumps([
            {"applicationId": "preserve-physical", "monitor": "HDMI-A-1",
             "monitorIdentity": {"manufacturer": "LG Electronics", "model": "LG ULTRAGEAR+", "serial": "LG-test"}},
            {"applicationId": "preserve-legacy", "monitor": "DP-1"},
        ], separators=(",", ":"))
        subprocess.run(["kwriteconfig6", "--file", "kwinrc", "--group", "Script-windowlayouts",
                        "--key", "ApplicationMappings", mappings], env=env, check=True)
        completed = subprocess.run(["bash", str(PROJECT / "install-drag-overlay.sh")], env=env,
                                   text=True, capture_output=True, timeout=30)
        assert (completed.returncode != 0) == fail, completed.stderr
        calls = [json.loads(line) for line in (root / "calls.jsonl").read_text().splitlines()]
        refreshes = [call for call in calls if call[0] == "systemd-run"
                     and "org.example.WindowLayouts.Configurator.Quit" in call]
        direct_quits = [call for call in calls if call[0] == "qdbus-qt6"
                        and "org.example.WindowLayouts.Configurator.Quit" in call]
        if skip and previous_version != CURRENT_VERSION and not fail:
            assert len(refreshes) == 1 and "--on-active=8s" in refreshes[0]
            assert calls[-1] == refreshes[0], "Refresh was scheduled before installation finished"
        else:
            assert not refreshes
        assert len(direct_quits) == (0 if skip else 1)
        assert (installed / "application_mappings.py").read_bytes() == (PROJECT / "helpers/application_mappings.py").read_bytes()
        preserved = subprocess.check_output([
            "kreadconfig6", "--file", "kwinrc", "--group", "Script-windowlayouts",
            "--key", "ApplicationMappings"], env=env, text=True).strip()
        assert preserved == mappings, "Upgrade changed saved application mappings"


scenario("1.3.1", skip=True)
scenario("1.4.0", skip=True)
scenario("1.4.1", skip=True)
scenario(CURRENT_VERSION, skip=True)
scenario("1.3.1", skip=False)
scenario("1.3.1", skip=True, fail=True)
print("Upgrade preserves mappings, installs the helper, and refreshes the service only after success")
