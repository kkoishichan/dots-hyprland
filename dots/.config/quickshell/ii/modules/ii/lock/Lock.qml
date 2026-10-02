pragma ComponentBehavior: Bound
import qs.modules.common.panels.lock

LockScreen {
    id: root

    // WlSessionLock in LockScreen covers every output directly. Keep the
    // current workspaces intact so unlock/reload/hotplug cannot strand them.
    lockSurface: LockSurface {
        context: root.context
    }
}
