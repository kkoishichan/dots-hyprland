#!/usr/bin/env node
// Export the lock screen's actual Material paths instead of approximating them.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const cache = new Map();
function load(file) {
    file = path.resolve(file);
    if (cache.has(file)) return cache.get(file);
    const context = vm.createContext({console});
    cache.set(file, context);
    const source = fs.readFileSync(file, 'utf8').replace(/^\.pragma .*$/mg, '').replace(/^\.import "([^"]+)" as (\w+)$/mg, (_, relative, name) => {
        context[name] = load(path.resolve(path.dirname(file), relative));
        return '';
    });
    const exports = Array.from(source.matchAll(/^(?:class|const|let)\s+(\w+)/gm), m => m[1]);
    vm.runInContext(source + '\nObject.assign(globalThis, {' + exports.join(',') + '});', context, {filename: file, timeout: 10000});
    return context;
}
const library = load(path.join(__dirname, '../dots/.config/quickshell/ii/modules/common/widgets/shapes/material-shapes.js'));
const names = ['Clover4Leaf', 'Arrow', 'Pill', 'SoftBurst', 'Diamond', 'ClamShell', 'Pentagon'];
const number = n => Number(n.toFixed(7));
const paths = names.map(name => {
    const cubics = library['get' + name]().cubics;
    return `M ${number(cubics[0].anchor0X)} ${number(cubics[0].anchor0Y)} ` + cubics.map(c =>
        'C ' + [c.control0X, c.control0Y, c.control1X, c.control1Y, c.anchor1X, c.anchor1Y].map(number).join(' ')
    ).join(' ') + ' Z';
});
process.stdout.write('// Generated from illogical-impulse Material shapes; Apache-2.0.\n.pragma library\nvar paths = ' + JSON.stringify(paths) + ';\n');
