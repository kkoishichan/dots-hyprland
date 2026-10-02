.pragma library

function address(value) {
    if (!value) return "";
    const text = String(value).toLowerCase();
    return text.startsWith("0x") ? text : "0x" + text;
}

function viewport(monitor) {
    const m = monitor || {};
    const scale = m.scale || 1;
    const rotated = (m.transform || 0) % 2 === 1;
    const reserved = m.reserved || [0, 0, 0, 0];
    return {
        x: (m.x || 0) + reserved[0],
        y: (m.y || 0) + reserved[1],
        width: Math.max(1, ((rotated ? m.height : m.width) || 1920) / scale - reserved[0] - reserved[2]),
        height: Math.max(1, ((rotated ? m.width : m.height) || 1080) / scale - reserved[1] - reserved[3])
    };
}

function windows(clients, workspaceId, monitor) {
    const view = viewport(monitor);
    const members = clients.filter(w => w.workspace?.id === workspaceId && w.mapped !== false
        && (!w.hidden || w.grouped?.length > 0));
    const result = members.map(w => {
        // A hidden tab shares its visible group's position. Offscreen columns are retained.
        const shown = w.hidden ? members.find(other => !other.hidden
            && w.grouped?.includes(other.address)) || w : w;
        const x = (shown.at?.[0] || 0) - view.x;
        const y = (shown.at?.[1] || 0) - view.y;
        const width = Math.max(1, shown.size?.[0] || 1);
        const height = Math.max(1, shown.size?.[1] || 1);
        const visibleWidth = Math.max(0, Math.min(x + width, view.width) - Math.max(x, 0));
        const visibleHeight = Math.max(0, Math.min(y + height, view.height) - Math.max(y, 0));
        return Object.assign({}, w, {
            localX: x, localY: y, layoutWidth: width, layoutHeight: height,
            viewFraction: visibleWidth * visibleHeight / (width * height)
        });
    });
    result.sort((a, b) => Number(a.floating) - Number(b.floating)
        || a.localX - b.localX || a.localY - b.localY
        || String(a.stableId || a.address).localeCompare(String(b.stableId || b.address)));
    return result;
}

function extent(windows, monitor) {
    const view = viewport(monitor);
    return {
        left: windows.reduce((x, w) => Math.min(x, w.localX - 4), 0),
        right: windows.reduce((x, w) => Math.max(x, w.localX + w.layoutWidth + 4), view.width)
    };
}
