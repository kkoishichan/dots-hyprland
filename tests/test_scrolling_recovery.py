"""Inject failures into the real QML services and actual overview pointer handlers."""

import json
import time
import unittest

import test_overview_handoff as handoff


@unittest.skipUnless(handoff.QS, "Quickshell is needed for isolated recovery checks")
class ScrollingRecoveryTests(unittest.TestCase):
    def exercise(self, probe):
        handoff.OverviewHandoffTests().exercise_drop("backend-recovery", probe)

    def wait_for(self, predicate, timeout=4):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.04)
        self.fail("Recovery condition did not become true")

    def drag_to(self, rpc, status, workspace):
        row = next(row for row in status()["rows"] if row["id"] == workspace)
        x, y = row["x"] + row["width"] * 0.8, row["y"] + row["height"] * 0.5
        rpc("press")
        rpc("move", x, y)
        time.sleep(0.24)
        self.assertEqual(status()["target"]["workspace"], workspace)
        rpc("release", x, y)

    def assert_idle(self, state):
        self.assertFalse(state["placing"] or state["dropping"] or state["dragging"], state)
        self.assertIsNone(state["current"])
        self.assertFalse(state["queue"] or state["awaiting"])
        self.assertTrue(all(row["slot"] is None for row in state["rows"]))

    def test_failed_start_releases_queue_and_allows_retry(self):
        def probe(base, rpc, status, events):
            executable = base / "hyprctl"
            command = executable.read_bytes()
            executable.unlink()
            self.drag_to(rpc, status, 11)
            self.wait_for(lambda: not status()["placing"] and not status()["dropping"])
            self.assert_idle(status())
            self.assertEqual(status()["nativeWorkspace"], 2)
            executable.write_bytes(command)
            executable.chmod(0o700)
            self.drag_to(rpc, status, 11)
            self.wait_for(lambda: status()["nativeWorkspace"] == 11 and not status()["dropping"])
            self.assert_idle(status())
        self.exercise(probe)

    def test_snapshot_timeout_and_late_reply_do_not_finish_next_drop(self):
        def probe(base, rpc, status, events):
            control = base / "query-control.json"
            control.write_text(json.dumps({"invalid": ["workspaces"]}))
            self.drag_to(rpc, status, 11)
            first_id = status()["requestId"]
            self.assertGreater(first_id, 0)
            self.wait_for(lambda: bool(status()["awaiting"]))
            self.wait_for(lambda: not status()["dropping"] and not status()["awaiting"], timeout=6)
            self.assert_idle(status())
            self.assertEqual(status()["nativeWorkspace"], 11)
            control.unlink()
            (base / "insertion-mode").write_text("slow")
            self.drag_to(rpc, status, 1)
            second_id = status()["requestId"]
            self.assertGreater(second_id, first_id)
            rpc("complete", first_id, "0xa", "false")
            rpc("complete", first_id, "0xa", "true")
            time.sleep(0.3)
            state = status()
            self.assertTrue(state["dropping"], "A stale reply ended the new drop")
            self.assertEqual(state["requestId"], second_id)
            self.assertIsNotNone(state["target"])
            self.assertEqual(state["nativeWorkspace"], 11)
            self.wait_for(lambda: status()["nativeWorkspace"] == 1 and not status()["dropping"])
            self.assert_idle(status())
        self.exercise(probe)

    def test_hung_command_expires_and_queue_recovers(self):
        def probe(base, rpc, status, events):
            (base / "insertion-mode").write_text("hang")
            self.drag_to(rpc, status, 11)
            self.wait_for(lambda: status()["current"] is not None)
            self.wait_for(lambda: not status()["placing"] and not status()["dropping"], timeout=6)
            self.assert_idle(status())
            self.assertEqual(status()["nativeWorkspace"], 2)
            self.drag_to(rpc, status, 11)
            self.wait_for(lambda: status()["nativeWorkspace"] == 11 and not status()["dropping"])
            self.assert_idle(status())
        self.exercise(probe)

    def test_classic_mode_cancels_pending_drops_and_disables_dynamic_commands(self):
        def probe(base, rpc, status, events):
            (base / "insertion-mode").write_text("hang")
            self.drag_to(rpc, status, 11)
            self.wait_for(lambda: status()["current"] is not None)
            rpc("setScrolling", "false")
            self.wait_for(lambda: not status()["placing"] and not status()["dropping"])
            self.assert_idle(status())
            original = status()
            self.assertFalse(original["enabled"])
            native = (base / "native.json").read_text()
            saved = {path: path.read_bytes() for path in base.rglob("scrolling-workspaces.json")}
            self.assertEqual(rpc("dynamicOps"), "0")
            time.sleep(0.3)
            self.assertEqual(status()["workspaceState"], original["workspaceState"])
            self.assertEqual((base / "native.json").read_text(), native)
            self.assertEqual({path: path.read_bytes() for path in saved}, saved)
            rpc("setScrolling", "true")
            self.wait_for(lambda: status()["enabled"])
            self.drag_to(rpc, status, 11)
            self.wait_for(lambda: status()["nativeWorkspace"] == 11 and not status()["dropping"])
            self.assert_idle(status())
        self.exercise(probe)

    def test_old_monitor_query_cannot_overwrite_new_focus_event(self):
        def probe(base, rpc, status, events):
            state_file = base / "native.json"
            native = json.loads(state_file.read_text())
            native["monitors"].append({"id": 1, "name": "other", "focused": False,
                "width": 2560, "height": 1440, "scale": 1, "x": 1920, "y": 0,
                "activeWorkspace": {"id": 3}})

            def save():
                temporary = state_file.with_suffix(".test-next")
                temporary.write_text(json.dumps(native))
                temporary.replace(state_file)

            save()
            (base / "query-control.json").write_text(json.dumps({"delays": {"monitors": 0.7}}))
            rpc("refresh")
            time.sleep(0.9)
            revision = status()["monitorRevision"]
            rpc("refresh")
            time.sleep(0.12)
            for monitor in native["monitors"]:
                monitor["focused"] = monitor["name"] == "other"
            save()
            events.settimeout(2)
            connection, _ = events.accept()
            try:
                connection.sendall(b"focusedmon>>other,3\n")
                self.wait_for(lambda: rpc("focused") == "other")
                self.wait_for(lambda: status()["monitorRevision"] > revision)
                state = status()
                self.assertEqual(state["snapshotFocus"], "mock", "Fixture missed the stale query")
                self.assertEqual(state["focused"], "other", "Old query reverted the event focus")
                self.wait_for(lambda: status()["snapshotFocus"] == "other")
                self.assertEqual(rpc("focused"), "other")
            finally:
                connection.close()
        self.exercise(probe)

    def test_return_to_scrolling_adopts_workspace_moves_made_in_tiling(self):
        def probe(base, rpc, status, events):
            rpc("setScrolling", "false")
            self.wait_for(lambda: not status()["enabled"])
            native_file = base / "native.json"
            native = json.loads(native_file.read_text())
            native["monitors"].append({"id": 1, "name": "other", "focused": False,
                "width": 2560, "height": 1440, "scale": 1, "x": 1920, "y": 0,
                "activeWorkspace": {"id": 2}})
            for ws in native["workspaces"]:
                if ws["id"] == 2: ws["monitor"] = "other"
            for window in native["clients"]:
                if window["workspace"]["id"] == 2: window["monitor"] = 1
            temporary = native_file.with_suffix(".test-next")
            temporary.write_text(json.dumps(native)); temporary.replace(native_file)
            revision = status()["monitorRevision"]
            rpc("refresh")
            self.wait_for(lambda: status()["monitorRevision"] > revision)
            time.sleep(0.45)  # All three fixture snapshots must have settled.
            previous = status()["dispatches"]
            rpc("setScrolling", "true")
            self.wait_for(lambda: status()["workspaceState"]["homes"].get("2") == "other")
            state = status()
            self.assertIn(2, state["workspaceState"]["orders"]["other"])
            self.assertNotIn(2, state["workspaceState"]["orders"]["mock"])
            self.assertEqual(state["dispatches"], previous,
                "Saved scrolling homes moved a workspace changed in tiling mode")
        self.exercise(probe)


if __name__ == "__main__":
    unittest.main()
