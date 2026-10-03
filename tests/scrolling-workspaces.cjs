const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const dir = __dirname + '/../dots/.config/quickshell/ii/services/';
function load(name) {
    const context = vm.createContext({});
    vm.runInContext(fs.readFileSync(dir + name, 'utf8').replace(/^\.pragma library\s*/, ''), context);
    return context;
}
const model = load('ScrollingWorkspaceModel.js');
const geometry = load('ScrollingGeometry.js');
const plain = x => JSON.parse(JSON.stringify(x));
const output = (id, name, active) => ({ id, name, activeWorkspace: { id: active } });
const workspace = (id, monitor, windows = 1, name = String(id)) => ({ id, monitor, windows, name });
let state = { orders: {}, homes: {}, nextId: 11 };
const initial = [workspace(1, 'laptop'), workspace(2, 'external'), workspace(3, 'external')];
function update(monitors, workspaces, pending = {}) {
    state = plain(model.reconcile(state, monitors, workspaces, [], pending, 100));
    return state;
}
update([output(0, 'laptop', 1), output(1, 'external', 2)], initial);
assert.deepEqual(state.orders.laptop, [1, 11]);
assert.deepEqual(state.orders.external, [2, 3, 12]);
const unchanged = JSON.stringify(state);
update([output(0, 'laptop', 1), output(1, 'external', 2)], initial);
assert.equal(JSON.stringify(state), unchanged, 'Polling must not allocate a new bottom workspace every time');
update([output(0, 'laptop', 1), output(1, 'external', 12)], initial.concat(workspace(12, 'external', 0)));
assert.deepEqual(state.orders.external, [2, 3, 12], 'Focusing bottom empty keeps a single bottom slot');
update([output(0, 'laptop', 1), output(1, 'external', 12)], initial.concat(workspace(12, 'external', 1)));
assert.deepEqual(state.orders.external, [2, 3, 12, 13], 'Opening a window on the bottom appends an empty slot');

// Insert before the first workspace while IPC snapshots still show the former active workspace.
state.orders.external.unshift(14); state.homes[14] = 'external'; state.nextId = 15;
update([output(0, 'laptop', 1), output(1, 'external', 2)], initial.concat(workspace(12, 'external')), {14: 1900});
assert.deepEqual(state.orders.external, [14, 2, 3, 12, 13]);
update([output(0, 'laptop', 1), output(1, 'external', 14)], initial.concat(workspace(12, 'external'), workspace(14, 'external', 0)));
assert.deepEqual(state.orders.external, [14, 2, 3, 12, 13], 'An active empty insertion survives');
update([output(0, 'laptop', 1), output(1, 'external', 2)], initial.concat(workspace(12, 'external'), workspace(14, 'external', 0)));
assert.deepEqual(state.orders.external, [2, 3, 12, 13], 'Leaving the empty insertion removes it');

// Reordering keeps stable IDs and survives reloading persisted state.
state.orders.external = [3, 2, 12, 13];
state = JSON.parse(JSON.stringify(state));
update([output(0, 'laptop', 1), output(1, 'external', 2)], initial.concat(workspace(12, 'external')));
assert.deepEqual(state.orders.external, [3, 2, 12, 13]);
update([output(0, 'laptop', 1), output(1, 'external', 2)], [initial[0], initial[1], workspace(3, 'external', 0), workspace(12, 'external')]);
assert.deepEqual(state.orders.external, [2, 12, 13], 'Closing the last window removes an inactive empty row');
update([output(0, 'laptop', 1), output(1, 'external', 2)], [initial[0], initial[1], workspace(8, 'external', 0, 'mail'), workspace(12, 'external')]);
assert.deepEqual(state.orders.external, [2, 12, 8, 13], 'Named empty workspaces remain available');
const beforeLock = state.orders.external.slice();
update([output(0, 'laptop', 1), output(1, 'external', 2147483646)], [initial[0]]);
assert.deepEqual(state.orders.external, beforeLock, 'Temporary lock IDs cannot replace the dynamic sequence');
assert(!Object.values(state.orders).flat().includes(2147483646));

const parked = state.orders.external.slice();
update([output(0, 'laptop', 1)], [workspace(1, 'laptop'), workspace(2, 'laptop'), workspace(12, 'laptop')]);
assert.deepEqual(state.orders.external, parked, 'Disconnected monitor order is remembered');
assert.equal(state.homes[2], 'external', 'Automatic migration retains the original monitor');
assert(state.orders.laptop.includes(2));
update([output(0, 'laptop', 1), output(1, 'external', 2)], [workspace(1, 'laptop'), workspace(2, 'external'), workspace(12, 'external')]);
assert(!state.orders.laptop.includes(2), 'Returning workspaces are removed from the temporary monitor sequence');

const monitor = { x: 320, y: 1440, width: 1920, height: 1200, scale: 1, reserved: [0, 40, 0, 0] };
const windows = plain(geometry.windows([
    {address:'0xb', workspace:{id:1}, mapped:true, hidden:false, visible:false, at:[1320,1484],size:[900,1152]},
    {address:'0xa', workspace:{id:1}, mapped:true, hidden:false, visible:false, at:[-580,1484],size:[900,1152]},
    {address:'0xc', workspace:{id:1}, mapped:false, at:[0,0],size:[100,100]},
], 1, monitor));
assert.deepEqual(windows.map(w => w.address), ['0xa', '0xb']);
assert.equal(windows[0].localX, -900, 'Negative offscreen coordinates are preserved');
assert.equal(windows[0].viewFraction, 0);
assert.equal(windows[1].localY, 4, 'Monitor origin and reserved top bar are subtracted');
assert.equal(geometry.extent(windows, monitor).left, -904);
assert.equal(geometry.viewport({width:3840,height:2160,scale:2,transform:1,reserved:[0,40,0,0]}).height, 1880);
assert.equal(geometry.address('AB12'), '0xab12');

// The same half-screen layout retains its capacity on both laptop and external outputs.
function columnsWithWidths(widths) {
    return widths.reduce((columns, width) => {
        const previous = columns[columns.length - 1];
        columns.push({ localX: previous ? previous.localX + previous.layoutWidth + 4 : 4, layoutWidth: width });
        return columns;
    }, []);
}
const caps = [];
for (const [viewportWidth, halfWidth] of [[1920, 954], [2560, 1274]]) {
    const halfColumns = columnsWithWidths(Array(8).fill(halfWidth));
    const cap = geometry.overviewWidth(halfColumns, viewportWidth, 0.18, 64);
    const filled = halfColumns.slice(0, 6);
    const filledWidth = filled[5].localX + filled[5].layoutWidth - filled[0].localX;
    assert(Math.abs(cap - (64 + (filledWidth + 8) * 0.18)) < 1e-8,
        `${viewportWidth}px: the maximum fits six complete half-screen columns`);
    assert.equal(geometry.overviewWidth(filled, viewportWidth, 0.18, 64), cap,
        'An exactly full row has the same width as an overflowing row');
    assert.equal(geometry.overviewWidth(halfColumns.slice(0, 2), viewportWidth, 0.18, 64), cap,
        'Closing windows retains the available whole-column capacity');
    assert.equal(geometry.overviewWidth([], viewportWidth, 0.18, 64), cap);
    assert.equal(geometry.overviewWidth(halfColumns.concat({ localX: 4, layoutWidth: 600 },
        { localX: 0, layoutWidth: 10000, floating: true }), viewportWidth, 0.18, 64), cap,
        'Stacked and floating windows do not count as extra columns');
    assert.equal(geometry.overviewWidth(halfColumns.map(w => ({ ...w, localX: w.localX - 4000 })),
        viewportWidth, 0.18, 64), cap, 'Scrolling the desktop does not resize the overview');
    const fullWidth = halfWidth * 2 + 4;
    for (const widths of [[fullWidth, halfWidth], [halfWidth, fullWidth]]) {
        assert(Math.abs(geometry.overviewWidth(columnsWithWidths(widths), viewportWidth, 0.18, 64)
            - cap) < 1e-8, `${viewportWidth}px: full and half columns retain the six-half-column cap in either order`);
    }
    caps.push(cap);
}
assert(caps[1] > caps[0], 'The larger output uses more space instead of retaining a fixed pixel cap');
const mixedColumns = columnsWithWidths([846, 1700, 1274, 846, 1700, 1700, 846]);
assert(Math.abs(geometry.overviewWidth(mixedColumns, 2560, 0.18, 64) - 1520.92) < 1e-8,
    'Mixed widths end after six complete columns and exclude the seventh');
const hidpi = geometry.viewport({ width: 3840, height: 2400, scale: 2 });
assert.equal(geometry.overviewWidth([], hidpi.width, 0.18, 64), caps[0],
    'HiDPI output sizing uses logical pixels');
assert.equal(geometry.overviewWidth([{ localX: 0, layoutWidth: 20000 }], 1920, 0.18, 64), 1152,
    'An oversized first column uses the available width rather than collapsing the card');
assert.equal(geometry.overviewWidth([{ localX: 0, layoutWidth: 20000, floating: true }], 1920, 0.18, 64), caps[0]);
assert.equal(geometry.overviewWidth([], 80, 0.18, 64), 48, 'Padding cannot push the card beyond a tiny output');
console.log('Dynamic workspace lifecycle, persistence, monitor migration and offscreen geometry: passed');
console.log('Responsive overview width, complete columns, stacking, mixed widths and HiDPI: passed');
