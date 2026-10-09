import QtQuick
import "../../../services/ScrollingGeometry.js" as Geometry

// One pointer grab owns a drag, even while its preview crosses layer surfaces.
QtObject {
    id: controller
    property var views: []
    property var sourceView: null
    property var sourceCard: null
    property var targetView: null
    property point pointer: Qt.point(0, 0)
    property point hotSpot: Qt.point(0.5, 0.5)
    property var sourceData: null
    property var sourceViewport: null
    property bool returning: false
    // Capture ownership outlives a card and the primary overview changing output.
    property var snapshots: ({})
    readonly property bool active: sourceView !== null
    readonly property string address: sourceData?.address ?? ""
    property Timer returnTimer: Timer {
        interval: controller.sourceView?.moveDuration ?? 200
        onTriggered: controller.finish()
    }

    function registerView(view) {
        if (!views.includes(view)) views = views.concat([view]);
        if (active) view.setSharedDrag(address, dataFor(view));
    }
    function rememberSnapshot(address, snapshot) {
        if (!address || !snapshot?.url || String(snapshots[address]?.url ?? "") === String(snapshot.url)) return;
        snapshots = Object.assign({}, snapshots, { [address]: snapshot });
    }
    function pruneSnapshots(addresses) {
        const alive = new Set(addresses);
        const closed = Object.keys(snapshots).filter(address => !alive.has(address));
        if (!closed.length) return;
        const retained = Object.assign({}, snapshots);
        for (const address of closed) delete retained[address];
        snapshots = retained;
    }
    function unregisterView(view) {
        if (view === sourceView || view === targetView) finish();
        views = views.filter(item => item !== view);
    }
    function dataFor(view) {
        return Geometry.projectWindow(sourceData, sourceViewport, view.viewport);
    }
    function begin(view, card, point, grab) {
        finish();
        sourceViewport = view.viewport;
        sourceData = card.windowData;
        sourceCard = card;
        sourceView = view;
        hotSpot = grab;
        for (const item of views) item.setSharedDrag(address, dataFor(item));
        update(point);
    }
    function update(point) {
        if (!active || returning || sourceCard.dropping) return;
        pointer = point;
        // Screen rectangles, rather than the overview's rounded card, decide
        // which output owns the pointer. An outside-card release still cancels.
        const next = views.find(view => view.acceptsGlobalPoint(point)) ?? null;
        if (targetView !== next) {
            if (targetView) targetView.clearDropTarget();
            targetView = next;
        }
        if (targetView) targetView.updateDragLocal(targetView.dragPointFromGlobal(point));
    }
    function commit(target) {
        for (const view of views) view.commitDrop(target);
    }
    function returnCard() {
        returning = true;
        for (const view of views) view.clearDragState();
        returnTimer.restart();
    }
    function finish() {
        returnTimer.stop();
        for (const view of views) view.clearDragState();
        targetView = null;
        sourceView = null;
        sourceCard = null;
        sourceData = null;
        sourceViewport = null;
        returning = false;
    }
}
