#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Validate mapping persistence and fresh-process detection, including PID reuse."""

import json
import os
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "helpers"))
from application_mappings import inspect_launch_process, process_token, validated_mappings

rule = {
    "applicationId": "org.kde.kate.desktop", "applicationName": "Kate",
    "layoutId": "WindowLayoutsRightHalf", "monitor": "DP-1",
    "windowRequirement": "documentWindow", "titleIncludes": "", "excludedTitles": ["Welcome"],
}
validated = validated_mappings([rule])
assert validated[0]["applicationId"] == "org.kde.kate"
assert validated_mappings(json.dumps(validated)) == validated
for field, value in (
    ("applicationId", ""), ("layoutId", "WindowLayoutsRestore"), ("monitor", ""),
    ("windowRequirement", "anything"), ("titleIncludes", "a\nb"),
    ("excludedTitles", [""]), ("excludedTitles", "Welcome"), ("wmClass", 3),
):
    invalid = {**rule, field: value}
    try:
        validated_mappings([invalid])
    except ValueError:
        pass
    else:
        raise AssertionError((field, value))
try:
    validated_mappings([rule, rule])
except ValueError:
    pass
else:
    raise AssertionError("duplicate app IDs accepted")
assert validated_mappings([{**rule, "layoutId": "custom:stable-id"}])

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)

    def write_process(pid, ticks, state="S"):
        path = root / str(pid)
        path.mkdir(exist_ok=True)
        (path / "stat").write_text(
            f"{pid} (an (unusual) process) {state} " + "0 " * 18 + str(ticks) + " 0 0\n"
        )

    write_process(101, 500)
    first = inspect_launch_process(101, "[]", root)
    assert first == {"token": "101:500", "previousAlive": False, "processes": ["101:500"]}
    assert inspect_launch_process(101, json.dumps(first["processes"]), root)["previousAlive"]
    # A second process while the first still lives belongs to the running app.
    write_process(102, 600)
    second = inspect_launch_process(102, json.dumps(first["processes"]), root)
    assert second["previousAlive"] and len(second["processes"]) == 2
    # Same numeric PID, different start tick: a fresh launch.
    write_process(101, 700)
    assert not inspect_launch_process(101, json.dumps(first["processes"]), root)["previousAlive"]
    write_process(101, 700, "Z")
    assert process_token(101, root) == ""
    assert process_token(-1, root) == ""
    assert process_token(12345, root) == ""

assert process_token(os.getpid()).startswith(f"{os.getpid()}:")
print("Application mapping validation and process lifecycle tests passed")
