#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Real KWin/Wayland acceptance test in an isolated D-Bus session and XDG roots.

Requires KWin, PySide6, GTK 3, dbus-python and the normal application runtime.
Never reads or changes the user's KWin settings or loads scripts in their session.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import traceback

PROJECT = Path(__file__).resolve().parents[1]


def qt_application():
    from PySide6.QtCore import QTimer
    from PySide6.QtWidgets import QApplication, QWidget
    app = QApplication([])
    app.setDesktopFileName("org.example.LaunchAcceptance")
    app.setQuitOnLastWindowClosed(False)
    launcher = QWidget()
    launcher.setWindowTitle("Templates — Launch Acceptance")
    launcher.resize(440, 300)
    launcher.show()
    windows = [launcher]

    def document():
        launcher.close()
        editor = QWidget()
        editor.setWindowTitle("acceptance.txt — Launch Acceptance")
        editor.resize(460, 320)
        editor.show()
        windows.append(editor)

    def another():
        extra = QWidget()
        extra.setWindowTitle("second.txt — Launch Acceptance")
        extra.resize(450, 310)
        extra.show()
        windows.append(extra)

    QTimer.singleShot(6000, document)
    QTimer.singleShot(11000, another)
    QTimer.singleShot(25000, app.quit)
    return app.exec()


def session():
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    name = dbus.service.BusName("org.example.LaunchAcceptance", bus=bus)
    snapshots = []

    class Recorder(dbus.service.Object):
        @dbus.service.method("org.example.LaunchAcceptance", in_signature="s", out_signature="")
        def Record(self, encoded):
            snapshots.append(json.loads(str(encoded)))

    recorder = Recorder(name, "/org/example/LaunchAcceptance")
    loop = GLib.MainLoop()
    errors = []
    root = Path(os.environ["XDG_CONFIG_HOME"]).parent

    def command(*args):
        return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT, timeout=15).strip()

    def wait_for(predicate, timeout=15):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            result = predicate()
            if result:
                return result
            time.sleep(.15)
        raise AssertionError("Timed out waiting for acceptance condition")

    def worker():
        processes = []
        logs = []
        try:
            kwin_log = (root / "kwin.log").open("w")
            logs.append(kwin_log)
            kwin = subprocess.Popen([
                "kwin_wayland", "--virtual", "--width", "1280", "--height", "720",
                "--output-count", "2", "--socket", "launch-acceptance", "--no-lockscreen",
                "--no-kactivities",
            ], stdout=kwin_log, stderr=subprocess.STDOUT)
            processes.append(kwin)
            wait_for(lambda: (Path(os.environ["XDG_RUNTIME_DIR"]) / "launch-acceptance").exists())
            os.environ["WAYLAND_DISPLAY"] = "launch-acceptance"
            os.environ["QT_QPA_PLATFORM"] = "wayland"
            os.environ["GDK_BACKEND"] = "wayland"
            subprocess.run([sys.executable, str(PROJECT / "tests/test-application-mappings-ui.py")],
                           check=True, timeout=20)
            observer = root / "observer.js"
            observer.write_text('''const timer = new QTimer(); timer.interval = 200;
timer.timeout.connect(() => callDBus("org.example.LaunchAcceptance", "/org/example/LaunchAcceptance",
"org.example.LaunchAcceptance", "Record", JSON.stringify({
outputs: workspace.screenOrder.map(o => ({name:o.name, x:o.geometry.x, width:o.geometry.width})),
windows: workspace.windowList().map(w => ({caption:w.caption, app:w.desktopFileName,
pid:w.pid, normal:w.normalWindow, transient:w.transient, modal:w.modal,
x:w.frameGeometry.x, y:w.frameGeometry.y, width:w.frameGeometry.width, height:w.frameGeometry.height}))
}))); timer.start();''')

            def load_script(path, plugin):
                number = command("qdbus-qt6", "org.kde.KWin", "/Scripting",
                                 "org.kde.kwin.Scripting.loadScript", str(path), plugin)
                assert int(number) >= 0, number
                command("qdbus-qt6", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.start")

            load_script(observer, "launch-acceptance-observer")
            wait_for(lambda: snapshots)
            output = snapshots[-1]["outputs"][1]
            # Model Opera GX's installed desktop ID differing from the window's
            # nonempty app ID; matching must use the saved StartupWMClass.
            rule = {"applicationId": "launch-acceptance-desktop-entry", "applicationName": "Launch Acceptance",
                    "wmClass": "org.example.LaunchAcceptance", "layoutId": "WindowLayoutsRightHalf", "monitor": output["name"],
                    "windowRequirement": "documentWindow", "titleIncludes": "", "excludedTitles": []}
            env = dict(os.environ)
            env["PYTHONPATH"] = os.pathsep.join((str(PROJECT / "helpers"),
                                                str(PROJECT / "cairo-dock-applet/window-layouts")))
            service_log = (root / "service.log").open("w")
            logs.append(service_log)
            service = subprocess.Popen([sys.executable, str(PROJECT / "helpers/window-layouts-configurator-service")],
                                       env=env, stdout=service_log, stderr=subprocess.STDOUT)
            processes.append(service)
            wait_for(lambda: service.poll() is not None or command(
                "qdbus-qt6", "org.freedesktop.DBus", "/org/freedesktop/DBus",
                "org.freedesktop.DBus.NameHasOwner", "org.example.WindowLayouts.Configurator") == "true")
            assert service.poll() is None, (root / "service.log").read_text()
            load_script(PROJECT / "packages/kwin-script/contents/code/main.js", "windowlayouts")
            # Save after the action script is already running, as the real
            # mapping editor does; test refresh as well as initial config load.
            command("kwriteconfig6", "--file", "kwinrc", "--group", "Script-windowlayouts",
                    "--key", "ApplicationMappings", json.dumps([rule]))
            command("qdbus-qt6", "org.kde.KWin", "/KWin", "org.kde.KWin.reconfigure")
            # Exercise the actual editor and its installed-application discovery.
            command("qdbus-qt6", "org.example.WindowLayouts.Configurator",
                    "/org/example/WindowLayouts/Configurator",
                    "org.example.WindowLayouts.Configurator.ShowApplicationMappings")
            wait_for(lambda: any(w["caption"] == "Application Launch Mappings" for w in snapshots[-1]["windows"]))
            print("Shared mapping editor opened successfully", flush=True)
            time.sleep(31)
            app = subprocess.Popen([sys.executable, __file__, "--application"])
            processes.append(app)

            def find(title):
                return next((w for w in snapshots[-1]["windows"] if w["caption"] == title), None)

            launcher = wait_for(lambda: find("Templates — Launch Acceptance"))
            launcher_geometry = (launcher["x"], launcher["y"], launcher["width"], launcher["height"])
            time.sleep(3)
            still_launcher = find("Templates — Launch Acceptance")
            assert still_launcher and (still_launcher["x"], still_launcher["y"], still_launcher["width"], still_launcher["height"]) == launcher_geometry
            expected_x = output["x"] + output["width"] // 2
            doc = wait_for(lambda: (w if (w := find("acceptance.txt — Launch Acceptance"))
                                   and abs(w["x"] - expected_x) <= 2
                                   and abs(w["width"] - output["width"] // 2) <= 2 else None))
            print(f"Launcher stayed in place; document mapped to {output['name']}: {doc}", flush=True)
            second = wait_for(lambda: find("second.txt — Launch Acceptance"))
            second_geometry = (second["x"], second["y"], second["width"], second["height"])
            time.sleep(3)
            extra = find("second.txt — Launch Acceptance")
            assert extra and (extra["x"], extra["y"], extra["width"], extra["height"]) == second_geometry
            assert abs(extra["width"] - output["width"] // 2) > 5
            print("Later window from the same process stayed in place", flush=True)
            assert service.poll() is None
            (root / "snapshots.json").write_text(json.dumps(snapshots, indent=2))
        except BaseException:
            errors.append(traceback.format_exc())
        finally:
            for process in reversed(processes):
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
            for log in logs:
                log.close()
            GLib.idle_add(loop.quit)

    thread = threading.Thread(target=worker)
    thread.start()
    loop.run()
    thread.join()
    if errors:
        print(errors[0], file=sys.stderr)
        print((root / "kwin.log").read_text()[-6000:], file=sys.stderr)
        print((root / "service.log").read_text()[-3000:] if (root / "service.log").exists() else "", file=sys.stderr)
        return 1
    print("Real KWin launch mapping integration passed")
    return 0


if __name__ == "__main__":
    if "--application" in sys.argv:
        raise SystemExit(qt_application())
    if "--session" in sys.argv:
        raise SystemExit(session())
    with tempfile.TemporaryDirectory(prefix="window-layouts-launch-acceptance-") as directory:
        root = Path(directory)
        env = dict(os.environ)
        for key, folder in (("XDG_CONFIG_HOME", "config"), ("XDG_DATA_HOME", "data"),
                            ("XDG_CACHE_HOME", "cache"), ("XDG_RUNTIME_DIR", "runtime")):
            path = root / folder
            path.mkdir(mode=0o700)
            env[key] = str(path)
        for key in ("DISPLAY", "WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "SESSION_MANAGER"):
            env.pop(key, None)
        env["KWIN_COMPOSE"] = "Q"
        env["NO_AT_BRIDGE"] = "1"
        env["GTK_USE_PORTAL"] = "0"
        env["QT_NO_XDG_DESKTOP_PORTAL"] = "1"
        completed = subprocess.run(["dbus-run-session", "--", sys.executable, __file__, "--session"], env=env)
        raise SystemExit(completed.returncode)
