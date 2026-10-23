#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Validate mapping persistence and fresh-process detection, including PID reuse."""

import json
import os
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "helpers"))
from application_mappings import (inspect_launch_process, process_token, validated_mappings,
                                  matching_monitors, monitor_label)

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


# Physical identity persists, follows connectors, and never guesses a legacy port.
identity = {"manufacturer": "LG Electronics", "model": "LG ULTRAGEAR+", "serial": "LG-123"}
physical_rule = {**rule, "monitorIdentity": identity}
assert validated_mappings([physical_rule])[0]["monitorIdentity"] == identity
lg = {"connector": "HDMI-A-1", "identity": identity}
other = {"connector": "DP-1", "identity": {**identity, "serial": "OTHER-123"}}
assert matching_monitors(physical_rule, [other, lg]) == [lg]
assert matching_monitors(rule, [other, lg]) == []
assert matching_monitors(physical_rule, [other]) == []
assert len(matching_monitors(physical_rule, [lg, {**lg, "connector": "DP-2"}])) == 2
assert "LG ULTRAGEAR+" in monitor_label(lg) and "LG-123" in monitor_label(lg)
for serial in ("", "0", "unknown", "none", "n/a"):
    no_serial = {**identity, "serial": serial}
    limited = {**rule, "monitorIdentity": no_serial}
    screen = {"connector": "DP-1", "identity": no_serial}
    assert matching_monitors(limited, [screen]) == [screen]
    assert matching_monitors(limited, [{**screen, "connector": "HDMI-A-1"}]) == []
    assert "tied to this port" in monitor_label(screen)
for invalid_identity in (None, [], "LG", {"serial": "123"}, {**identity, "serial": 123},
                         {**identity, "model": "bad\nmodel"}, {**identity, "serial": "x" * 513}):
    try:
        validated_mappings([{**rule, "monitorIdentity": invalid_identity}])
    except ValueError:
        pass
    else:
        raise AssertionError(invalid_identity)

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
