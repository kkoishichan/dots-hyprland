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

// Native cross-output moves preserve the column's fraction of the usable width.
// Floating windows keep their pixel size; tiled previews fill the new output's height.
function projectWindow(window, source, destination) {
    if (!window || !source || !destination) return window;
    if (window.floating) return Object.assign({}, window, {
        localX: Math.max(0, Math.min(destination.width - window.layoutWidth, window.localX)),
        localY: Math.max(0, Math.min(destination.height - window.layoutHeight, window.localY))
    });
    return Object.assign({}, window, {
        layoutWidth: window.layoutWidth * destination.width / source.width,
        layoutHeight: window.layoutHeight * destination.height / source.height,
        localY: window.localY * destination.height / source.height
    });
}

function insertion(windows, draggedAddress, x) {
    const dragged = windows.find(w => w.address === draggedAddress);
    const excluded = new Set([draggedAddress, ...(dragged?.grouped || [])]);
    const columns = [];
    windows.filter(w => !w.floating && !w.hidden && !excluded.has(w.address))
        .sort((a, b) => a.localX - b.localX).forEach(w => {
            const right = w.localX + w.layoutWidth;
            const previous = columns[columns.length - 1];
            if (previous && w.localX < previous.right) previous.right = Math.max(previous.right, right);
            else columns.push({ left: w.localX, right, address: w.address });
        });
    for (let i = 0; i < columns.length; i++) {
        const c = columns[i];
        if (x < (c.left + c.right) / 2) {
            return { anchor: c.address, before: true,
                x: i ? (columns[i - 1].right + c.left) / 2 : c.left - 2 };
        }
    }
    const last = columns[columns.length - 1];
    return { anchor: last?.address || "", before: false, x: last ? last.right + 2 : 0 };
}

// Lay out a drag as if it had already happened, without changing native metadata.
// The reserved window is also the released card's immediate animation target.
function dragPreview(windows, workspaceId, dragged, target, viewportWidth) {
    if (!dragged) return { windows, slot: null };
    const excluded = new Set([dragged.address, ...(dragged.grouped || [])]);
    const receiving = target?.workspace === workspaceId;
    if (!receiving && !windows.some(w => excluded.has(w.address))) return { windows, slot: null };
    const columns = [];
    windows.filter(w => !w.floating).sort((a, b) => a.localX - b.localX).forEach(w => {
        const right = w.localX + w.layoutWidth;
        const previous = columns[columns.length - 1];
        if (previous && w.localX < previous.right) {
            previous.right = Math.max(previous.right, right);
            previous.windows.push(w);
        } else columns.push({ left: w.localX, right, windows: [w] });
    });
    const gaps = columns.slice(1).map((c, i) => Math.max(0, c.left - columns[i].right));
    const gap = gaps.length ? Math.min(...gaps) : 4;
    const remaining = columns.map(c => ({ left: c.left, windows: c.windows.filter(w => !excluded.has(w.address)) }))
        .filter(c => c.windows.length).map(c => Object.assign(c, {
            right: Math.max(...c.windows.map(w => w.localX + w.layoutWidth))
        }));
    let index = remaining.findIndex(c => c.windows.some(w => w.address === target?.anchor));
    index = index < 0 ? remaining.length : index + (target.before ? 0 : 1);
    let slot = null;
    if (receiving && !dragged.floating) {
        slot = Object.assign({}, dragged, { workspace: { id: workspaceId }, localY: dragged.localY });
        remaining.splice(index, 0, { left: 0, right: dragged.layoutWidth, windows: [slot] });
    }
    // Keep the desktop's current origin. An empty destination centres its sole window.
    let x = columns[0]?.left ?? (receiving ? (viewportWidth - dragged.layoutWidth) / 2 : 4);
    const positions = {};
    for (const column of remaining) {
        for (const w of column.windows) {
            positions[w.address] = Object.assign({}, w, { localX: x + w.localX - column.left });
        }
        if (column.windows[0] === slot) {
            positions[slot.address].localX = x;
            slot = positions[slot.address];
        }
        x += column.right - column.left + gap;
    }
    const result = windows.filter(w => !excluded.has(w.address)).map(w => positions[w.address] ?? w);
    if (receiving) {
        // Floating clients retain their native placement rather than becoming a tiled column.
        if (dragged.floating) slot = Object.assign({}, dragged, { workspace: { id: workspaceId } });
        result.push(slot);
    }
    return { windows: result, slot };
}

function overviewWidth(windows, viewportWidth, scale, padding) {
    // Use the monitor's logical width. A larger monitor gets a larger budget,
    // while fractional scaling and output rotation are handled by viewport().
    const maximumWidth = Math.max(1, viewportWidth * 0.6);
    const chrome = padding + 8 * scale; // Fixed padding and extent's four-pixel edges.
    const budget = (maximumWidth - chrome) / scale;
    if (budget <= 0) return maximumWidth;

    const columns = [];
    windows.filter(w => !w.floating).sort((a, b) => a.localX - b.localX).forEach(w => {
        const previous = columns[columns.length - 1];
        const right = w.localX + w.layoutWidth;
        // Stacked windows and grouped tabs share a column, including narrower clients.
        if (previous && w.localX < previous.right) previous.right = Math.max(previous.right, right);
        else columns.push({ left: w.localX, right });
    });

    let span;
    if (!columns.length) {
        // Empty/floating-only rows keep the default half-screen capacity.
        const width = Math.max(1, viewportWidth / 2 - 6);
        const count = Math.floor((budget + 4 + 1e-7) / (width + 4));
        span = count * (width + 4) - 4;
    } else {
        const left = columns[0].left;
        const occupied = columns[columns.length - 1].right - left;
        if (occupied <= budget + 1e-7) {
            // Keep spare slots when all windows fit. The narrowest whole column
            // is independent of focus/order and handles full + half widths.
            const width = Math.min(...columns.map(c => c.right - c.left));
            const gaps = columns.slice(1).map((c, i) => c.left - columns[i].right);
            const gap = gaps.length ? Math.min(...gaps) : 4;
            span = occupied + Math.floor((budget - occupied + 1e-7) / (width + gap)) * (width + gap);
        } else {
            // Overflowing rows end at the last complete column within budget.
            span = 0;
            for (const column of columns) {
                const next = column.right - left;
                if (next > budget + 1e-7) break;
                span = next;
            }
        }
    }
    // An oversized first column stays scrollable in the full available width.
    return span > 0 ? Math.min(maximumWidth, chrome + span * scale) : maximumWidth;
}
