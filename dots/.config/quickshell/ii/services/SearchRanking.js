.pragma library

function parseQuery(query, prefixes) {
    const text = String(query).trim();
    const modes = ["clipboard", "emojis", "shellCommand", "webSearch", "app", "action", "math"];
    for (const mode of modes) {
        const prefix = prefixes[mode];
        if (!prefix || !text.startsWith(prefix)) continue;
        const rest = text.slice(prefix.length);
        // "/usr/bin/foo" is an absolute command path, not an action named "usr".
        if (mode === "action" && /^\S*\//.test(rest)) continue;
        return { mode: mode, text: rest.trim() };
    }
    return { mode: "default", text: text };
}

function normalized(text) {
    return String(text || "").toLowerCase().trim();
}

// Descriptions, categories and long command lines remain useful fallback
// matches, but cannot push a web search or command out of the first few rows.
function applicationRelevance(query, entry) {
    const text = normalized(query);
    if (!text) return 0;
    const name = normalized(entry.name);
    const id = normalized(entry.id).replace(/\.desktop$/, "").split(".").pop();
    if (name === text || id === text) return 3;
    if (name.startsWith(text) || id.startsWith(text)) return 2;
    if (text.length >= 2 && (name.includes(text) || id.includes(text))) return 1;
    if (text.length >= 2 && normalized(entry.genericName).includes(text)) return 1;
    if (Array.from(entry.keywords || []).some(word => normalized(word) === text)) return 1;
    return 0;
}

function groupApplications(query, entries) {
    const ranked = Array.from(entries).map((entry, index) => ({
        entry: entry, index: index, relevance: applicationRelevance(query, entry)
    })).sort((a, b) => b.relevance - a.relevance || a.index - b.index);
    const leadingCount = Math.min(3, ranked.filter(match => match.relevance > 0).length);
    return {
        all: ranked.map(match => match.entry),
        leading: ranked.slice(0, leadingCount).map(match => match.entry),
        trailing: ranked.slice(leadingCount, 8).map(match => match.entry)
    };
}

// Named calls only count for math functions; "Steam (Runtime)" is an app name.
const MATH_FUNCTIONS = ["abs", "acos", "asin", "atan", "cbrt", "ceil", "cos", "cosh", "deg", "exp",
    "factorial", "floor", "gcd", "lcm", "ln", "log", "log10", "log2", "max", "min", "mod", "rad",
    "root", "round", "sin", "sinh", "sqrt", "tan", "tanh", "trunc"];

function isCalculation(text) {
    // A year or a phrase starting with digits is not automatically a calculation.
    const call = /^([a-z][a-z0-9_]*)\s*\(.+\)$/i.exec(text);
    return (/\d/.test(text) && /^[\d\s.,()+\-*/%^!]+$/.test(text) && /[+\-*/%^!]/.test(text))
        || /^(pi|π|e|tau|phi)$/i.test(text)
        || (call !== null && MATH_FUNCTIONS.includes(call[1].toLowerCase()))
        || (/^[-+]?\d/.test(text) && /(?:\s+(?:to|in)\s+|->)/i.test(text));
}

function mayCalculate(text) {
    // qalc can interpret ordinary words as products of unit abbreviations, and
    // exits successfully for names such as "qt6ct" or "1password". Keep that
    // fallback behind '=' instead of inventing answers for prose.
    return /^[-+]?\d+(?:[.,]\d+)?$/.test(text) || isCalculation(text);
}

function orderResults(mode, apps, actions, web, command, math, showDefaults, calculation) {
    if (mode === "webSearch") return web ? [web] : [];
    if (mode === "shellCommand") return command ? [command] : [];
    if (mode === "math") return math ? [math] : [];
    if (mode === "action") return actions;
    if (mode === "app") return apps.all;

    let results = calculation && math ? [math] : [];
    results = results.concat(apps.leading);
    if (showDefaults) results = results.concat([web, command, calculation ? null : math].filter(Boolean));
    return results.concat(apps.trailing);
}
