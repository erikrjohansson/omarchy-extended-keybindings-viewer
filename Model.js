.pragma library

// Turns `omarchy menu keybindings` records into the key map's list: the
// bindings for exactly one modifier combination, or the ones matching a
// search. Pure functions, no QML.

var MODS = ["SUPER", "SHIFT", "CTRL", "ALT"]

// How a key is written in a combo, e.g. "SUPER + BKSP".
var LABELS = {
    "ESCAPE": "ESC", "BACKSPACE": "BKSP", "DELETE": "DEL", "PRINT": "PRT",
    "MINUS": "-", "EQUAL": "=", "COMMA": ",", "PERIOD": ".", "SLASH": "/",
    "SEMICOLON": ";", "APOSTROPHE": "'", "GRAVE": "`", "BACKSLASH": "\\",
    "BRACKETLEFT": "[", "BRACKETRIGHT": "]", "LEFT": "←", "RIGHT": "→",
    "UP": "↑", "DOWN": "↓", "DIGITS": "1 … 0", "ARROWS": "ARROWS"
}

var DIGITS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
var ARROWS = ["LEFT", "DOWN", "UP", "RIGHT"]
var DIRECTION = /\b(left|right|up|down|above|below|top|bottom)\b/gi

function family(b) {
    var upper = b.key.toUpperCase()
    if (DIGITS.indexOf(upper) !== -1) return "DIGITS"
    if (ARROWS.indexOf(upper) !== -1) return "ARROWS"
    return ""
}

function keyLabel(b) {
    var upper = b.key.toUpperCase()
    if (/^XF86/i.test(b.key)) return b.key.slice(4)
    var scroll = { "MOUSE_UP": "↑", "MOUSE_DOWN": "↓", "MOUSE_LEFT": "←", "MOUSE_RIGHT": "→" }[upper]
    if (scroll) return "SCROLL " + scroll
    if (upper === "MOUSE:275") return "BACK MOUSE"
    if (upper === "MOUSE:276") return "FORWARD MOUSE"
    if (LABELS[upper]) return LABELS[upper]
    return upper.replace(/ BUTTON$/, "")
}

// `extended-keybindings-viewer keys` output → { layout, codes: { keycode: NAME },
// keys: { NAME: [level1, level2] } (shown), resKeys (the layout bindings are
// matched against, when different), chars: { keysym: text },
// codeBinds: { "modmask,description": keycode }, universal: count }
function parseLayout(text) {
    var out = { layout: "", codes: {}, keys: {}, resKeys: {}, chars: {}, codeBinds: {}, universal: 0 }
    var aliases = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; ++i) {
        var f = lines[i].split("\t")
        if (f[0] === "layout") out.layout = f[1] || ""
        else if (f[0] === "code") out.codes[f[1]] = f[2] || ""
        else if (f[0] === "alias") aliases.push(f)
        else if (f[0] === "res") out.resKeys[f[1]] = [f[2] || "", f[3] || ""]
        else if (f[0] === "char") out.chars[f[1]] = f.slice(2).join("\t")
        else if (f[0] === "universal") out.universal = f[1] === "?" ? "?" : Number(f[1]) || 0
        else if (f[0] === "bind") out.codeBinds[f[1] + "," + f.slice(3).join("\t")] = f[2]
        else if (f.length >= 2 && f[0]) out.keys[f[0]] = [f[1] || "", f[2] || ""]
    }
    // Key events name a key by keycode; use the name the symbols use, which
    // may be an alias (the Menu key's symbols are on <MENU>, an alias of <COMP>).
    for (var a = 0; a < aliases.length; ++a) {
        var alias = aliases[a][1], real = aliases[a][2]
        if (!out.keys[alias] || out.keys[real]) continue
        for (var code in out.codes) if (out.codes[code] === real) out.codes[code] = alias
    }
    return out
}

var MASKS = { "SHIFT": 1, "CTRL": 4, "ALT": 8, "SUPER": 64 }

// Mouse bindings → the parts of the drawn mouse.
var MOUSE = {
    "LEFT MOUSE BUTTON": "BTN_LEFT", "RIGHT MOUSE BUTTON": "BTN_RIGHT",
    "MIDDLE MOUSE BUTTON": "BTN_MIDDLE", "MOUSE:275": "BTN_SIDE", "MOUSE:276": "BTN_EXTRA",
    "MOUSE_UP": "WHEEL_UP", "MOUSE_DOWN": "WHEEL_DOWN", "MOUSE_LEFT": "WHEEL_LEFT", "MOUSE_RIGHT": "WHEEL_RIGHT"
}

function modmask(mods) {
    var mask = 0
    for (var i = 0; i < mods.length; ++i) mask += MASKS[mods[i]] || 0
    return mask
}

// Sets each binding's keyId to the drawn key it is pressed on with the active
// layout, or "" when none. A binding made on a physical key (code:NN) is on
// that key, and its combo is relabelled with what the key shows there (via
// `label`); otherwise it is on the key that types its symbol (base level
// first, then shifted).
function resolve(bindings, layout, drawn, label) {
    // Every key of the layout counts (a media key is found even though it is
    // not drawn); drawn keys and base levels win, as they are filled in last.
    // Hyprland matches bindings against its first layout (resKeys), which is
    // not necessarily the one shown on the keys.
    var symbols = Object.keys(layout.resKeys || {}).length ? layout.resKeys : layout.keys
    var bySym = {}
    var all = Object.keys(symbols).filter(function(n) { return drawn.indexOf(n) === -1 }).concat(drawn)
    for (var level = 1; level >= 0; --level)
        for (var d = 0; d < all.length; ++d) {
            var syms = symbols[all[d]]
            if (syms && syms[level]) bySym[syms[level].toLowerCase()] = all[d]
        }
    // Some symbols sit on several keys (XF86AudioPlay is on two keycodes);
    // pressing any of them finds the binding.
    var keysOf = {}
    for (var n = 0; n < all.length; ++n) {
        var s = symbols[all[n]]
        // Base level only: Hyprland matches a key by its unmodified symbol.
        for (var l = 0; l < 1; ++l) if (s && s[l]) {
            var sym = s[l].toLowerCase()
            if (!keysOf[sym]) keysOf[sym] = []
            if (keysOf[sym].indexOf(all[n]) === -1) keysOf[sym].push(all[n])
        }
    }
    return bindings.map(function(b) {
        var copy = {}
        for (var k in b) copy[k] = b[k]
        var code = layout.codeBinds[modmask(b.mods) + "," + b.desc]
        var name = code ? layout.codes[code] : ""
        if (name) {
            // A physical key that is not drawn can still be looked up.
            copy.keyId = name
            var text = drawn.indexOf(name) !== -1 ? label(name) : ""
            if (text && text !== keyLabel(b)) copy.combo = combo(b.mods, text === "+" ? "PLUS" : text)
        } else {
            var mouse = MOUSE[b.key.toUpperCase()]
            copy.keyId = mouse !== undefined ? mouse : /MOUSE/i.test(b.key) ? "" : bySym[b.key.toLowerCase()] || ""
        }
        copy.keyNames = name && copy.keyId === name ? [name] : copy.keyId ? keysOf[b.key.toLowerCase()] || [copy.keyId] : []
        return copy
    })
}

function sortMods(mods) {
    return mods.slice().sort(function(a, b) { return MODS.indexOf(a) - MODS.indexOf(b) })
}

function combo(mods, key) {
    return sortMods(mods).concat(key ? [key] : []).join(" + ")
}

// "SUPER SHIFT + RETURN    → Browser<TAB>exec<TAB>omarchy-launch-browser"
function parse(text) {
    var out = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; ++i) {
        var fields = lines[i].split("\t")
        var arrow = fields[0].indexOf("→")
        if (arrow < 0) continue
        var keys = fields[0].slice(0, arrow).trim()
        var plus = keys.lastIndexOf(" + ")
        var mods = plus < 0 ? [] : keys.slice(0, plus).split(/\s+/).filter(function(m) { return MODS.indexOf(m) !== -1 })
        var key = plus < 0 ? keys : keys.slice(plus + 3).trim()
        var b = {
            index: out.length, desc: fields[0].slice(arrow + 1).trim(), mods: sortMods(mods), key: key,
            keyId: "", dispatcher: fields[1] || "", arg: fields.slice(2).join("\t")
        }
        b.family = family(b)
        b.combo = combo(b.mods, keyLabel(b))
        out.push(b)
    }
    return out
}

// Descriptions that differ only by the digit or direction of their key share
// a line, so "Switch to workspace 1 … 10" reads as one entry.
function signature(b) {
    if (b.family === "DIGITS") return b.desc.replace(/\b(10|[0-9])\b/g, "#")
    if (b.family === "ARROWS") return b.desc.replace(/\bto the (left|right)\b/gi, "$1").replace(DIRECTION, "◆")
    return b.desc
}

// The keys a merged line covers: "1 … 0" only when all ten are bound,
// otherwise the real range ("1 … 9") or the keys themselves ("1, 3").
function familyLabel(name, bindings) {
    var order = name === "DIGITS" ? ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"] : ["LEFT", "UP", "DOWN", "RIGHT"]
    var at = []
    for (var i = 0; i < bindings.length; ++i) {
        var n = order.indexOf(bindings[i].key.toUpperCase())
        if (n !== -1 && at.indexOf(n) === -1) at.push(n)
    }
    at.sort(function(a, b) { return a - b })
    if (at.length === order.length) return LABELS[name]
    if (name === "DIGITS" && at.length >= 3 && at[at.length - 1] - at[0] === at.length - 1)
        return order[at[0]] + " … " + order[at[at.length - 1]]
    var sep = name === "DIGITS" ? ", " : " "
    return at.map(function(n) { return name === "DIGITS" ? order[n] : LABELS[order[n]] }).join(sep)
}

function mergedText(name, sig) {
    if (name === "DIGITS") return sig.replace(/\s*#$/, "").replace(/#/g, "N")
    return sig.replace(/◆/g, "←→")
}

function hasAll(mods, wanted) {
    for (var i = 0; i < wanted.length; ++i) if (mods.indexOf(wanted[i]) === -1) return false
    return true
}

function matches(b, terms) {
    var hay = (b.combo + " " + b.desc + " " + b.key).toLowerCase()
    for (var t = 0; t < terms.length; ++t) if (hay.indexOf(terms[t]) === -1) return false
    return true
}

// The list to show: every binding that uses at least `mods` (null: all, in
// Omarchy's order), on `key` (a key name) when given, matching `query`. With
// `mods` the exact combination comes first, then those adding modifiers.
// Each line: { combo, text, mods, keys, bindings }
function list(bindings, mods, query, key) {
    var terms = String(query || "").toLowerCase().split(/\s+/).filter(function(t) { return t.length })
    var byKey = {}
    var out = []
    for (var i = 0; i < bindings.length; ++i) {
        var b = bindings[i]
        if (mods && !hasAll(b.mods, mods)) continue
        if (key && (b.keyNames || [b.keyId]).indexOf(key) === -1) continue
        if (terms.length && !matches(b, terms)) continue
        var merge = b.family ? b.family + "|" + b.mods.join("+") + "|" + signature(b) : "#" + b.index
        var line = byKey[merge]
        if (!line) {
            line = byKey[merge] = { combo: b.combo, text: b.desc, mods: b.mods, keys: [], bindings: [], family: b.family, sig: signature(b) }
            out.push(line)
        }
        line.bindings.push(b)
        if (b.keyId && line.keys.indexOf(b.keyId) === -1) line.keys.push(b.keyId)
    }
    if (mods) out.sort(function(a, b) { return a.mods.length - b.mods.length || a.bindings[0].index - b.bindings[0].index })
    for (var l = 0; l < out.length; ++l) {
        var ln = out[l]
        // A merged line names every key it covers, whether or not the
        // description itself carried the digit or direction.
        if (ln.bindings.length > 1) {
            if (ln.sig !== ln.bindings[0].desc) ln.text = mergedText(ln.family, ln.sig)
            ln.combo = combo(ln.mods, familyLabel(ln.family, ln.bindings))
        }
    }
    return out
}

// Splits lines into columns, filled top to bottom.
function columns(lines, count) {
    var perColumn = Math.max(1, Math.ceil(lines.length / count))
    var cols = []
    for (var i = 0; i < lines.length; i += perColumn) cols.push(lines.slice(i, i + perColumn))
    return cols
}

// What a line lights up on the keyboard.
function litKeys(line) {
    return line ? line.mods.concat(line.keys) : []
}
