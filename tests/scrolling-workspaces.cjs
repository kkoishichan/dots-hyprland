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

// Cap the overview at complete native columns, including the actual gaps and padding.
const halfColumns = Array.from({length: 8}, (_, i) => ({ localX: 4 + i * 1278, layoutWidth: 1274 }));
const overviewCap = geometry.overviewWidth(halfColumns, 2560, 0.18, 1100, 64);
assert(Math.abs(overviewCap - 984.88) < 1e-8, 'The HDMI cap contains four complete columns');
assert.equal(geometry.overviewWidth(halfColumns.slice(0, 4), 2560, 0.18, 1100, 64), overviewCap,
    'An exactly full workspace uses the same cap as an overflowing workspace');
assert.equal(geometry.overviewWidth(halfColumns.slice(0, 2), 2560, 0.18, 1100, 64), overviewCap,
    'Few windows do not collapse the maximum width');
assert.equal(geometry.overviewWidth([], 2560, 0.18, 1100, 64), overviewCap);
assert.equal(geometry.overviewWidth(halfColumns, 2560, 0.18, overviewCap, 64), overviewCap,
    'A boundary-sized cap must not lose a column through floating-point rounding');
assert.equal(geometry.overviewWidth(halfColumns.concat({ localX: 4, layoutWidth: 600 },
    { localX: 0, layoutWidth: 10000, floating: true }), 2560, 0.18, 1100, 64), overviewCap,
    'Stacked and floating windows do not count as extra columns');
const mixedColumns = [846, 1700, 1274, 846, 1700].reduce((columns, width) => {
    const previous = columns[columns.length - 1];
    columns.push({ localX: previous ? previous.localX + previous.layoutWidth + 4 : 4, layoutWidth: width });
    return columns;
}, []);
assert(Math.abs(geometry.overviewWidth(mixedColumns, 2560, 0.18, 1100, 64) - 907.48) < 1e-8,
    'Different column widths retain their proportions and the fifth column is excluded');
console.log('Dynamic workspace lifecycle, persistence, monitor migration and offscreen geometry: passed');
console.log('Overview width, complete columns, stacking and mixed widths: passed');
