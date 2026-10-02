.pragma library

const MAX_ID = 1000000;

function validId(id) {
    return Number.isInteger(id) && id > 0 && id < MAX_ID;
}

function reconcile(state, monitors, workspaces, clients, pending, now) {
    const orders = {};
    const homes = Object.assign({}, state.homes || {});
    const oldOrders = state.orders || {};
    const byId = {};
    const occupied = {};
    const used = new Set();
    const names = monitors.map(m => m.name);
    for (const ids of Object.values(oldOrders)) for (const id of ids) used.add(id);
    for (const ws of workspaces) {
        if (!validId(ws.id)) continue;
        byId[ws.id] = Object.assign({}, ws);
        used.add(ws.id);
        if (ws.windows > 0) occupied[ws.id] = true;
    }
    for (const win of clients) {
        const id = win.workspace?.id;
        if (!validId(id) || win.mapped === false) continue;
        occupied[id] = true;
        used.add(id);
        if (!byId[id]) {
            byId[id] = { id, name: String(id), monitor: monitors.find(m => m.id === win.monitor)?.name };
        }
    }
    for (const mon of monitors) if (validId(mon.activeWorkspace?.id)) {
        const id = mon.activeWorkspace.id;
        used.add(id);
        if (!byId[id]) byId[id] = { id, name: String(id), monitor: mon.name };
        else byId[id].monitor = mon.name;
    }
    let nextId = Math.max(11, state.nextId || 11);
    function allocate(name) {
        while (used.has(nextId)) nextId++;
        if (nextId >= MAX_ID) throw new Error("Dynamic workspace ID range exhausted");
        const id = nextId++;
        used.add(id);
        homes[id] = name;
        return id;
    }
    function named(id) {
        return byId[id] && byId[id].name !== String(id);
    }
    for (const name of Object.keys(oldOrders)) {
        // Keep the original sequence while a monitor is disconnected.
        if (!names.includes(name)) orders[name] = oldOrders[name].slice();
    }
    for (const mon of monitors) {
        const old = oldOrders[mon.name] || [];
        const active = mon.activeWorkspace?.id;
        if (!validId(active)) {
            orders[mon.name] = old.slice(); // Lock-screen transition: do not replace the user's sequence.
            continue;
        }
        const owned = id => !byId[id] || byId[id].monitor === mon.name;
        let bottom = old.length ? old[old.length - 1] : null;
        if (!bottom || occupied[bottom] || named(bottom) || !owned(bottom)) bottom = null;
        const ids = old.filter(id => validId(id) && owned(id)
            && (occupied[id] || named(id) || id === active || (pending[id] || 0) > now)
            && id !== bottom);
        const discovered = Object.values(byId).filter(ws => ws.monitor === mon.name
            && (occupied[ws.id] || named(ws.id) || ws.id === active || (pending[ws.id] || 0) > now))
            .sort((a, b) => a.id - b.id);
        for (const ws of discovered) {
            if (ws.id !== bottom && !ids.includes(ws.id)) ids.push(ws.id);
            if (!homes[ws.id] || names.includes(homes[ws.id])) homes[ws.id] = mon.name;
        }
        if (bottom === null) {
            const last = ids[ids.length - 1];
            // An active empty workspace at the end is already the bottom empty workspace.
            if (last === active && !occupied[last] && !named(last)) bottom = ids.pop();
            else bottom = allocate(mon.name);
        }
        ids.push(bottom);
        orders[mon.name] = ids;
    }
    const retained = new Set(Object.values(orders).reduce((all, ids) => all.concat(ids), []));
    for (const id of Object.keys(homes)) if (!retained.has(Number(id)) && !occupied[id] && !named(Number(id))) delete homes[id];
    return { version: 1, orders, homes, nextId };
}
