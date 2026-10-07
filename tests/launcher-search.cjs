const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ranking = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../dots/.config/quickshell/ii/services/SearchRanking.js'), 'utf8')
    .replace(/^\.pragma library\s*/, ''), ranking);
const plain = value => JSON.parse(JSON.stringify(value));
const prefixes = { clipboard: ';', emojis: ':', shellCommand: '$', webSearch: '?', app: '>', action: '/', math: '=' };
const web = { name: 'web' }, command = { name: 'command' }, math = { name: 'math' };
const fallback = Array.from({ length: 40 }, (_, i) => ({
    name: `Unrelated application ${i}`, id: `other-${i}`, comment: 'weather git status C++'
}));
const app = { name: 'Kitty', id: 'kitty.desktop', genericName: 'Terminal emulator' };
function results(query, entries = fallback, showDefaults = true, mathResult = null) {
    const intent = ranking.parseQuery(query, prefixes);
    if (intent.mode === 'math' || ranking.isCalculation(intent.text)) mathResult = math;
    return plain(ranking.orderResults(intent.mode, ranking.groupApplications(intent.text, entries),
        [{ name: 'action' }], web, command, mathResult, showDefaults, ranking.isCalculation(intent.text)));
}
assert.deepEqual(results('weather tomorrow').slice(0, 2), [web, command]);
assert.deepEqual(results('git status').slice(0, 2), [web, command]);
assert.equal(results('weather tomorrow').length, 10, 'Only eight fallback applications are shown');
assert.deepEqual(results('kitty', [...fallback, app]).slice(0, 3), [app, web, command]);
assert.deepEqual(results('terminal', [{ name: 'kitty', genericName: 'Terminal emulator' }]).slice(0, 1),
    [{ name: 'kitty', genericName: 'Terminal emulator' }]);
assert.equal(results('微信', [{ name: '微信', id: 'wechat' }])[0].name, '微信');
const manyStrong = Array.from({ length: 20 }, (_, i) => ({ name: `Browser ${i}`, id: `browser-${i}` }));
assert.deepEqual(results('browser', manyStrong).slice(3, 5), [web, command], 'Actions are always among the first five rows');
assert.deepEqual(results(' ? C++ & Linux '), [web]);
assert.deepEqual(results('$ git status'), [command]);
assert.deepEqual(results('= 2+2'), [math]);
assert.deepEqual(results('/dark'), [{ name: 'action' }]);
assert.equal(results('>browser', manyStrong).length, 20, 'Explicit application mode retains all matching apps');
assert.equal(results('2026 linux news')[0].name, 'web', 'A year must not become a calculator result');
assert.equal(results('2*(3+4)')[0].name, 'math');
assert.equal(results('sqrt(2)')[0].name, 'math');
assert.equal(results('10 cm to inch')[0].name, 'math');
assert.equal(results('pi')[0].name, 'math');
assert.equal(ranking.mayCalculate('git status'), false);
assert.equal(ranking.mayCalculate('42'), true);
assert.equal(ranking.mayCalculate('sqrt(2)'), true);
// qalc exits successfully for app names; only explicit calculations reach it without '='.
for (const name of ['Steam (Runtime)', 'obs (studio)', 'qt6ct', '1password', '2026 linux news']) {
    assert.equal(ranking.mayCalculate(name), false, name);
    assert.equal(ranking.isCalculation(name), false, name);
}
assert.equal(results('Steam (Runtime)', [{ name: 'Steam (Runtime)', id: 'steam' }])[0].name, 'Steam (Runtime)');
assert.equal(ranking.mayCalculate('10 cm to inch'), true);
assert.equal(ranking.mayCalculate('-3.5'), true);
assert.deepEqual(results('42', fallback, true, math).slice(0, 3), [web, command, math],
    'A valid non-priority math result stays ahead of weak application matches');
assert.deepEqual(results('browser', manyStrong, true, math).slice(3, 6), [web, command, math],
    'All three quick actions remain adjacent and visible');
assert.equal(results('kitty', [app], false)[0].name, 'Kitty');
assert(!results('kitty', [app], false).some(entry => ['web', 'command'].includes(entry.name)));
assert.deepEqual(plain(ranking.parseQuery('; clipboard text', prefixes)), { mode: 'clipboard', text: 'clipboard text' });
assert.deepEqual(plain(ranking.parseQuery(': smile', prefixes)), { mode: 'emojis', text: 'smile' });
// An absolute command path is not the '/' action prefix.
assert.deepEqual(plain(ranking.parseQuery('/usr/bin/foo --flag', prefixes)), { mode: 'default', text: '/usr/bin/foo --flag' });
assert.deepEqual(results('/usr/bin/foo --flag').slice(0, 2), [web, command]);
assert.deepEqual(plain(ranking.parseQuery('/wall dark', prefixes)), { mode: 'action', text: 'wall dark' });
console.log('Launcher relevance, bounded fallback results, explicit modes and action visibility: passed');
