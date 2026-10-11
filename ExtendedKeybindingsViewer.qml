import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui as Ui
import "Model.js" as Model

// SUPER + K as a key map: a keyboard that lights up the keys of the binding
// you point at, a search bar, and the bindings for exactly the modifiers you
// hold. Typing filters the list. Nothing runs from here: the plugin's
// bindings.lua puts Hyprland in an empty submap while the overlay is open, and
// lookups stay off until that submap is confirmed active.
Item {
    id: root

    property var shell: null
    property var manifest: null
    property bool opened: false

    readonly property string pluginId: "io.github.erikrjohansson.extended-keybindings-viewer"
    readonly property string helper: String(Qt.resolvedUrl("extended-keybindings-viewer")).replace(/^file:\/\//, "")
    readonly property var modOrder: ["SUPER", "SHIFT", "CTRL", "ALT"]

    property var rawBindings: []
    property var layout: ({ layout: "", codes: {}, keys: {}, resKeys: {}, chars: {}, codeBinds: {}, universal: 0 })
    property bool loaded: false
    property string loadError: ""
    readonly property string submapName: "io.github.erikrjohansson.extended-keybindings-viewer"
    // True once Hyprland is confirmed to be in the key map's empty submap; only
    // then are shortcuts looked up (otherwise pressing one would run it).
    property bool guarded: false
    property bool guardChecked: false
    property string setupState: ""        // "setup" / "not-setup", from the helper
    property bool settingUp: false
    property bool testHooks: false
    property string shapeSetting: ""      // "iso" / "ansi" from extensions/extended-keybindings-viewer.json
    // A card over the desktop like Omarchy's menus, or the whole screen; the
    // choice is kept in the same settings file.
    property bool fullscreen: false
    // A toggle waiting to be saved, and the text to save.
    property bool saveWanted: false
    property string settingsOut: ""
    // The page is shown once the bindings and the layout have been read (they
    // are read ahead when the shell starts and kept between openings), so the
    // keyboard never opens half drawn and then jumps into place.
    property bool layoutRead: false
    property bool showAnyway: false
    readonly property bool ready: (loaded && layoutRead) || showAnyway
    property string recordsText: ""
    property string layoutText: ""
    // Each binding lit on the key that types it on the active layout.
    readonly property var bindings: Model.resolve(rawBindings, layout, keyboard.keyNames,
                                                  function(name) { return keyboard.labels(name)[0] })
    // Layouts sold on ANSI keyboards; everything else is drawn as ISO.
    readonly property var ansiLayouts: ["", "us", "ru", "ua", "by", "kz", "kr", "cn", "tw", "th", "il", "ara", "ir", "in", "br"]
    readonly property bool iso: shapeSetting === "iso" ? true
                              : shapeSetting === "ansi" ? false
                              : ansiLayouts.indexOf(layout.layout) === -1
    property var baseMods: []
    property var heldMods: []
    property string query: ""
    // The full shortcut being pressed (modifiers + key), until its key is released.
    // The shortcut being pressed, set in one assignment so that a press or a
    // release changes the list once: { key, mods }.
    property var lookup: ({ key: "", mods: [] })
    readonly property string pinnedKey: lookup.key
    readonly property var pinnedMods: lookup.mods
    property bool typing: false
    // Keyboard focus is in one of three places: the keyboard (every key is a
    // lookup), the search box (`typing`), or the list (`inList`, arrows move).
    property bool inList: false
    property int cursor: -1
    property int hoverIndex: -1
    property string hoverKey: ""
    property var targetScreen: Quickshell.screens[0] || null
    // The pointer only points at something once it has moved: not where it
    // happened to rest when the page opened, nor at whatever the list puts
    // under it when it changes.
    property bool pointerArmed: false
    property point lastPointer: Qt.point(-1, -1)

    function pointerAt(p) {
        if (lastPointer.x < 0) { lastPointer = p; return }
        if (Math.abs(p.x - lastPointer.x) + Math.abs(p.y - lastPointer.y) < 3) return
        lastPointer = p
        pointerArmed = true
    }

    function disarmPointer() {
        pointerArmed = false
        lastPointer = Qt.point(-1, -1)
        hoverIndex = -1
        hoverKey = ""
    }

    // With nothing held or clicked the list shows every binding. Holding (or
    // clicking) modifiers shows the bindings that use them, exact ones first.
    // While typing in the search, modifiers are for typing, not a filter.
    readonly property var filterHeld: typing ? [] : heldMods
    readonly property bool pinned: pinnedKey !== ""
    readonly property var activeMods: pinned ? pinnedMods : modOrder.filter(function(m) {
        return baseMods.indexOf(m) !== -1 || filterHeld.indexOf(m) !== -1
    })
    readonly property bool searching: query.length > 0
    readonly property bool modFilter: activeMods.length > 0
    // Read straight from the inputs (not from the derived properties above,
    // which update one after another) and reused while the view is the same:
    // every new list updates every row.
    readonly property var lines: viewLines(bindings, lookup, baseMods, filterHeld, query)
    property var linesMemo: ({ bindings: null, key: "", lines: [] })
    function viewLines(all, look, base, held, text) {
        var mods = look.key ? look.mods : modOrder.filter(function(m) {
            return base.indexOf(m) !== -1 || held.indexOf(m) !== -1
        })
        var key = (look.key ? "key " + look.key : "text " + text) + " mods " + mods.join("+")
        var memo = linesMemo
        if (memo.bindings !== all || memo.key !== key) {
            memo.bindings = all
            memo.key = key
            memo.lines = look.key ? Model.list(all, mods, "", look.key) : Model.list(all, mods.length ? mods : null, text)
        }
        return memo.lines
    }
    // Whether the pressed combination itself is bound (it is then listed first).
    readonly property bool pinnedExact: pinned && lines.length > 0 && lines[0].mods.join("+") === pinnedMods.join("+")
    readonly property string pinnedCombo: pinned
        ? pinnedMods.concat([pinnedLabel]).join(" + ") : ""
    readonly property string pinnedLabel: {
        var text = keyboard.labels(pinnedKey)[0]
        if (text === "+") return "PLUS"
        if (text) return text
        if (pinnedKey === "SPCE") return "SPACE"
        // Keys that are not drawn (media keys) are named by their symbol.
        var sym = (layout.keys[pinnedKey] || [""])[0]
        return sym ? (layout.chars[sym] || sym.replace(/^XF86/, "")) : pinnedKey
    }
    readonly property int columnCount: Math.max(1, Math.min(gridColumns, Math.ceil(lines.length / 6)))
    readonly property var cols: Model.columns(lines, columnCount)
    readonly property int perColumn: cols.length ? cols[0].length : 1
    function perColumnFor(count) {
        return count ? Math.ceil(count / Math.max(1, Math.min(gridColumns, Math.ceil(count / 6)))) : 1
    }

    // Everything one list row slot shows, from the inputs in one go: the row
    // then changes once per view, never with half-updated parts (a row
    // briefly at its old place counted as near the view and laid out its
    // text for nothing). Text is laid out only in and near the visible part
    // of the list: doing it for every row on each key press was most of the cost.
    function rowAt(i, all, top, height) {
        if (i >= all.length) return null
        var per = perColumnFor(all.length)
        var y = (i % per) * lineHeight
        return { line: all[i], x: Math.floor(i / per) * columnStep, y: y,
                 near: y + lineHeight > top - lineHeight * 4 && y < top + height + lineHeight * 4 }
    }
    // Rows the list keeps, enough for the full list (or any longer view).
    readonly property int slotCount: Math.max(allLines.length, lines.length)
    readonly property var cursorLine: cursor >= 0 && cursor < lines.length ? lines[cursor] : null
    readonly property var keyLine: lineForKey(hoverKey)
    // Repeater delegates get copies of the line objects, so lines are
    // compared by index, never by identity.
    readonly property var hoverLine: hoverIndex >= 0 && hoverIndex < lines.length ? lines[hoverIndex] : null
    readonly property var activeLine: hoverLine || keyLine || cursorLine
    readonly property int activeIndex: activeLine ? lines.indexOf(activeLine) : -1
    readonly property var shownMods: activeLine ? activeLine.mods : activeMods
    readonly property var lit: activeLine ? Model.litKeys(activeLine) : pinned ? pinnedMods.concat([pinnedKey]) : []
    readonly property var boundKeys: {
        var out = {}
        for (var i = 0; i < lines.length; ++i)
            for (var k = 0; k < lines[i].keys.length; ++k) out[lines[i].keys[k]] = true
        return out
    }

    // The theme's menu tokens, so the key map looks like Omarchy's own menus.
    readonly property color fg: Color.menu.text
    readonly property color accent: Color.menu.selectedText
    readonly property color selectedFill: Color.menu.selectedBackground
    readonly property color selectedBorder: Color.menu.selectedBorder
    readonly property string fontFamily: Style.font.menuFamily
    readonly property real radius: Math.min(Style.cornerRadius, Style.space(10))
    // One grid for the whole page: three list columns sized to the longest
    // combination and description of all bindings (so nothing moves while
    // filtering), the keyboard scaled to the same width, the title and the
    // filter label on its edges and the search box over the middle column.
    readonly property var allLines: Model.list(bindings, null, "")
    readonly property int longestCombo: {
        var n = 10
        for (var j = 0; j < allLines.length; ++j) n = Math.max(n, allLines[j].combo.length)
        return Math.min(n, 30)
    }
    readonly property int longestText: {
        var n = 20
        for (var j = 0; j < allLines.length; ++j) n = Math.max(n, allLines[j].text.length)
        return Math.min(n, 40)
    }
    readonly property real charWidth: Math.max(1, metrics.averageCharacterWidth)
    readonly property real gutter: Style.space(28)
    readonly property real rowPad: Style.space(10)
    readonly property real comboWidth: charWidth * (longestCombo + 2)
    // In a row: at most 60 % of the column, so a description always has room.
    readonly property real rowComboWidth: Math.min(comboWidth, columnWidth * 0.6)
    // As many columns as fit (up to three), so narrow screens and large fonts
    // still leave every description room.
    readonly property real columnNeed: comboWidth + charWidth * (longestText + 1)
    // Windowed, the page is a card no taller than frameMaxHeight. It is as
    // wide as the keyboard at the size that height allows, so the keyboard
    // keeps the page's edges, unless that leaves room for only one list
    // column: then it widens for two (narrowed a little if need be, cut-off
    // rows showing their full text), with the keyboard centred.
    readonly property real cardPad: Math.min(Style.space(36), panel.width * 0.025)
    readonly property real cardBorder: Math.max(1, Style.space(2))
    readonly property real cardInset: cardPad + cardBorder
    // Windowed: a landscape card on large screens (70 % of the height), most
    // of the height on small ones (never under 600 px when the screen allows).
    readonly property real frameMaxHeight: fullscreen ? panel.height
        : Math.min(panel.height - 2 * Math.max(Style.space(24), panel.height * 0.07),
                   Math.max(600, panel.height * 0.7))
    readonly property real heightUnit: frameMaxHeight * 0.29 / 6.25
    readonly property real keyboardWidth: heightUnit * keyboard.units
    readonly property real maxContent: fullscreen ? panel.width - Style.space(64)
        : Math.min(panel.width * 0.8, panel.width - 2 * Style.space(48)) - 2 * cardInset
    function columnsIn(width, need) {
        return Math.max(1, Math.min(3, Math.floor((width + gutter) / (need + gutter))))
    }
    function columnsWidth(n) { return n * columnNeed + (n - 1) * gutter }
    readonly property int alignedColumns: columnsIn(fullscreen ? maxContent : Math.min(keyboardWidth, maxContent), columnNeed)
    readonly property int gridColumns: Math.max(alignedColumns, Math.min(2, columnsIn(maxContent, columnNeed * 0.8)))
    readonly property real contentWidth: fullscreen
        ? Math.min(maxContent, Math.max(panel.width * 0.5, columnsWidth(gridColumns)))
        : Math.min(maxContent, columnsWidth(gridColumns))
    readonly property real lineHeight: Math.round(Style.font.title * 2.1)
    // Sized for the full list, so the card does not change size while filtering.
    readonly property int fullColumns: Math.max(1, Math.min(gridColumns, Math.ceil(allLines.length / 6)))
    readonly property real cardHeight: Math.min(frameMaxHeight,
        flick.y + Math.ceil(allLines.length / fullColumns) * lineHeight + 2 * cardInset)
    // A column is as wide as its text needs (less when that does not fit);
    // spare width goes between the columns, so the first starts at the
    // page's left edge and the last ends at its right edge.
    readonly property real columnWidth: Math.min(columnNeed, gridColumns > 1
        ? (contentWidth - (gridColumns - 1) * gutter) / gridColumns : contentWidth)
    readonly property real columnStep: gridColumns > 1 ? (contentWidth - columnWidth) / (gridColumns - 1) : 0
    // A single column of results sits in the middle, under the search box.
    readonly property real listOffset: cols.length === 1 ? (contentWidth - columnWidth) / 2 : 0
    // Bindings Hyprland keeps active in every submap still run while the key
    // map is open; "?" when that could not be checked.
    // Unknown ("?") at every opening until this opening's layout read says;
    // the warning waits for that read to finish, so it never flashes.
    property var universalCount: "?"
    property bool layoutDone: false
    readonly property string universalWarning: universalCount === "?"
        ? "Could not check for shortcuts that stay active while this is open"
        : universalCount > 0 ? universalCount + (universalCount === 1 ? " shortcut stays" : " shortcuts stay") + " active while this is open (marked universal)" : ""
    readonly property real unit: Math.max(16, Math.min(contentWidth / keyboard.units, heightUnit))

    function lineForKey(id) {
        if (!id) return null
        for (var i = 0; i < lines.length; ++i) if (lines[i].keys.indexOf(id) !== -1) return lines[i]
        return null
    }

    function open(payloadJson) {
        var monitor = Hyprland.focusedMonitor
        var screens = Quickshell.screens
        for (var i = 0; i < screens.length; ++i)
            if (monitor && screens[i].name === monitor.name) targetScreen = screens[i]
        baseMods = []
        heldMods = []
        query = ""
        lookup = { key: "", mods: [] }
        typing = false
        inList = false
        cursor = -1
        hoverIndex = -1
        hoverKey = ""
        // Kept loaded between openings, but each opening starts at the top.
        baseY = 0
        flick.contentY = 0
        opened = true
        disarmPointer()
        loadError = ""
        universalCount = "?"
        layoutDone = false
        guarded = false
        guardChecked = false
        guardSerial++
        showAnyway = false
        if (!ready) showTimer.restart()
        read()
        if (!statusProc.running) statusProc.running = true
        testFlag.reload()
        Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }

    // Bindings, layout and settings; again at every opening, in case they changed.
    function read() {
        if (!records.running) records.running = true
        if (!layoutProc.running) layoutProc.running = true
        loadTimeout.restart()
        settingsFile.reload()
    }

    Component.onCompleted: read()

    // A slow read still opens the page soon, saying it is reading.
    Timer { id: showTimer; interval: 600; onTriggered: root.showAnyway = true }

    // Saved into the file as it is now (read again first), so other settings
    // and edits made meanwhile are kept.
    function toggleFullscreen() {
        fullscreen = !fullscreen
        saveWanted = true
        settingsFile.reload()
    }

    // The settings as read: an object, or null when the file is not one (it
    // is then left alone).
    function applySettings(parsed) {
        shapeSetting = String((parsed || {}).shape || "").toLowerCase()
        if (!saveWanted) {
            fullscreen = !!parsed && parsed.fullscreen === true
            return
        }
        saveWanted = false
        if (!parsed) return
        parsed.fullscreen = fullscreen
        settingsOut = JSON.stringify(parsed, null, 2) + "\n"
        if (!settingsDir.running) settingsDir.running = true
    }

    // Closed, nothing is left running: the instance stays loaded all session.
    function close() {
        opened = false
        heldMods = []
        clearPin()
        pinnedButton = ""
        restoring = false
        leftHold.stop()
        wheelRelease.stop()
        showTimer.stop()
        guardCheck.stop()
        guardAgain = false
    }

    function dismiss() {
        close()
        if (shell) shell.hide(pluginId)
    }

    function toggleMod(mod) {
        var next = baseMods.slice()
        var at = next.indexOf(mod)
        if (at === -1) next.push(mod)
        else next.splice(at, 1)
        baseMods = next
    }

    // A modifier is recognised by the physical key and what the layout puts on
    // it, not by the event's keysym: with `shift:both_capslock_cancel`,
    // releasing left Shift reports Caps_Lock, and swapped keys (ctrl:swapcaps)
    // follow the layout. Until the layout is read, the usual keycodes are used.
    readonly property var modScanCodes: ({ 50: "SHIFT", 62: "SHIFT", 37: "CTRL", 105: "CTRL",
                                            64: "ALT", 133: "SUPER", 134: "SUPER" })

    function modForEvent(event) {
        var name = layout.codes[event.nativeScanCode]
        if (name && layout.keys[name]) return keyboard.modOf(name)
        return modScanCodes[event.nativeScanCode] || modForKey(event.key)
    }

    function modForKey(key) {
        if (key === Qt.Key_Shift) return "SHIFT"
        if (key === Qt.Key_Control) return "CTRL"
        if (key === Qt.Key_Alt) return "ALT"
        if (key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R) return "SUPER"
        return ""
    }

    // Rebuilt from the event's modifier flags on every key event, so a lost
    // release event cannot leave a modifier stuck. The flags may or may not
    // include the modifier key being pressed or released, so that key is
    // applied on top.
    function syncMods(event, down) {
        var flags = event.modifiers
        var next = []
        if (flags & Qt.MetaModifier) next.push("SUPER")
        if (flags & Qt.ShiftModifier) next.push("SHIFT")
        if (flags & Qt.ControlModifier) next.push("CTRL")
        if (flags & Qt.AltModifier) next.push("ALT")
        var mod = modForEvent(event)
        if (mod) {
            next = next.filter(function(m) { return m !== mod })
            if (down) next.push(mod)
        }
        if (next.slice().sort().join() !== heldMods.slice().sort().join()) heldMods = next
    }

    function pin(mods, name) {
        if (!guarded) return
        var sorted = modOrder.filter(function(m) { return mods.indexOf(m) !== -1 })
        // Key repeat presses the same shortcut again: nothing changes.
        if (lookup.key === name && lookup.mods.join("+") === sorted.join("+")) return
        hoverIndex = -1
        hoverKey = ""
        lookup = { key: name, mods: sorted }
    }

    // A click or scroll to look up: Super + click, a right or middle click, or
    // a scroll with a modifier held. Plain left clicks and scrolling are for
    // the page itself.
    readonly property var buttonIds: ({ 1: "BTN_LEFT", 2: "BTN_RIGHT", 4: "BTN_MIDDLE", 8: "BTN_SIDE", 16: "BTN_EXTRA" })
    property string pinnedButton: ""

    function modsOf(flags) {
        var out = []
        if (flags & Qt.MetaModifier) out.push("SUPER")
        if (flags & Qt.ShiftModifier) out.push("SHIFT")
        if (flags & Qt.ControlModifier) out.push("CTRL")
        if (flags & Qt.AltModifier) out.push("ALT")
        return out
    }

    // A plain left click on something usable (the search box, the list, the
    // setup notice, the fullscreen button, a key or a part of the drawn mouse) is
    // for the page; anywhere else it is a lookup like other buttons.
    function onPageControl(mouse) {
        var items = [searchBox, flick, keyboard, notice, sizeButton]
        for (var i = 0; i < items.length; ++i) {
            if (!items[i].visible) continue
            var p = items[i].mapFromItem(null, mouse.x, mouse.y)
            if (items[i] === keyboard ? keyboard.controlAt(p.x, p.y) : items[i].contains(p)) return true
        }
        return false
    }

    function pressButton(mouse) {
        var mods = modsOf(mouse.modifiers)
        var id = buttonIds[mouse.button]
        if (!guarded) return false
        if (!id || (mouse.button === Qt.LeftButton && !mods.length && onPageControl(mouse))) return false
        if (typing) stopSearch()
        if (inList) leaveList(false)
        pinnedButton = id
        // A quick plain left click (to leave the search or the list) is no
        // lookup; held a moment, it shows what uses the left button.
        if (mouse.button === Qt.LeftButton && !mods.length) leftHold.restart()
        else pin(mods, id)
        return true
    }

    function releaseButton(mouse) {
        leftHold.stop()
        if (pinnedButton && buttonIds[mouse.button] === pinnedButton && pinnedKey === pinnedButton) clearPin()
        pinnedButton = ""
    }

    Timer {
        id: leftHold
        interval: 200
        onTriggered: if (root.pinnedButton === "BTN_LEFT") root.pin([], "BTN_LEFT")
    }

    // Lookups and held modifiers are temporary views: the full list comes
    // back where it was scrolled to.
    readonly property bool baseView: !pinned && !modFilter && !searching
    property real baseY: 0
    // Restored once the change has settled (the rows are in place by then);
    // not when another view has started meanwhile.
    property bool restoring: false
    function restoreScroll() {
        restoring = false
        if (!opened || !baseView) return
        flick.contentY = Math.max(0, Math.min(baseY, flick.contentHeight - flick.height))
    }
    onBaseViewChanged: {
        restoring = baseView
        if (baseView) Qt.callLater(restoreScroll)
    }

    function scrollLookup(wheel) {
        var mods = modsOf(wheel.modifiers)
        var dx = wheel.angleDelta.x, dy = wheel.angleDelta.y
        if (!guarded || !mods.length || (dx === 0 && dy === 0)) return false
        pin(mods, Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? "WHEEL_LEFT" : "WHEEL_RIGHT")
                                              : (dy > 0 ? "WHEEL_UP" : "WHEEL_DOWN"))
        wheelRelease.restart()
        return true
    }

    // A part of the drawn mouse, pressed with the left button: its bindings
    // show while it is held.
    function pressPart(id) {
        if (typing) stopSearch()
        if (inList) leaveList(false)
        pin(heldMods, id)
    }

    function releasePart(id) {
        if (pinnedKey === id) clearPin()
    }

    // A scroll has no release; the lookup shows while scrolling goes on.
    Timer {
        id: wheelRelease
        interval: 700
        onTriggered: if (/^WHEEL_/.test(root.pinnedKey)) root.clearPin()
    }

    function clearPin() {
        if (lookup.key) lookup = { key: "", mods: [] }
    }

    function startSearch() {
        clearPin()
        inList = false
        search.forceActiveFocus()
    }

    function stopSearch() {
        query = ""
        keyCatcher.forceActiveFocus()
    }

    // Entered while modifiers are held the list may be empty for a moment;
    // the first row is selected once there is one.
    function enterList(at) {
        clearPin()
        hoverIndex = -1
        hoverKey = ""
        cursor = at !== undefined ? at : lines.length ? Math.max(0, cursor) : -1
        inList = true
        keyCatcher.forceActiveFocus()
    }

    // Back to the search when it has text, else to the keyboard.
    function leaveList(toSearch) {
        inList = false
        if (toSearch && searching) { search.forceActiveFocus(); return }
        if (!searching) cursor = -1
        keyCatcher.forceActiveFocus()
    }

    // Ctrl+Tab: keyboard → search → list → keyboard; Ctrl+Shift+Tab backwards.
    function nextPlace() {
        if (typing) { if (lines.length) enterList(); else keyCatcher.forceActiveFocus() }
        else if (inList) leaveList(false)
        else startSearch()
    }

    function previousPlace() {
        if (typing) keyCatcher.forceActiveFocus()
        else if (inList) { inList = false; startSearch() }
        else enterList()
    }

    // The key map's own shortcuts (Ctrl+Tab, Ctrl+Shift+Tab, Ctrl+F,
    // Ctrl+Shift+F for fullscreen), unless a binding uses exactly that
    // combination. Returns true when handled.
    function navigate(event) {
        var mods = heldMods.slice().sort().join("+")
        if (mods !== "CTRL" && mods !== "CTRL+SHIFT") return false
        if (event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab && event.key !== Qt.Key_F) return false
        if (isBound(heldMods, layout.codes[event.nativeScanCode] || "")) return false
        if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && mods === "CTRL+SHIFT")) previousPlace()
        else if (event.key === Qt.Key_Tab) nextPlace()
        else if (event.key === Qt.Key_F && mods === "CTRL") startSearch()
        else if (event.key === Qt.Key_F && mods === "CTRL+SHIFT") { if (!event.isAutoRepeat) toggleFullscreen() }
        else return false
        return true
    }

    // Whether a binding uses exactly this combination; such a press is always
    // a lookup, even when it is one of the key map's own shortcuts.
    function isBound(mods, name) {
        var found = Model.list(bindings, mods, "", name)
        return found.length > 0 && found[0].mods.join("+") === modOrder.filter(function(m) {
            return mods.indexOf(m) !== -1 }).join("+")
    }

    // Left / right in the list: the same row in the neighbouring column.
    function moveColumn(step) {
        if (cursor < 0) { move(1); return }
        hoverIndex = -1
        hoverKey = ""
        var column = Math.floor(cursor / perColumn) + step
        if (column < 0 || column >= cols.length) return
        cursor = column * perColumn + Math.min(cursor % perColumn, cols[column].length - 1)
    }

    function move(step) {
        if (!lines.length) return
        hoverIndex = -1
        hoverKey = ""
        if (cursor < 0) cursor = step > 0 ? 0 : lines.length - 1
        else cursor = Math.max(0, Math.min(lines.length - 1, cursor + step))
    }

    function selectKey(id) {
        if (modOrder.indexOf(id) !== -1) { toggleMod(id); return }
        var line = lineForKey(id)
        if (line) cursor = lines.indexOf(line)
    }

    // Reads the inputs directly: derived properties may not have caught up yet.
    onLinesChanged: {
        disarmPointer()
        var exact = lookup.key !== "" && lines.length > 0 && lines[0].mods.join("+") === lookup.mods.join("+")
        cursor = (query.length > 0 || inList || exact) && lines.length ? 0 : -1
        hoverIndex = -1
        if (!lines.length && !heldMods.length) inList = false
        Qt.callLater(ensureCursorVisible)
    }
    onCursorChanged: Qt.callLater(ensureCursorVisible)
    onPerColumnChanged: Qt.callLater(ensureCursorVisible)
    onLineHeightChanged: Qt.callLater(ensureCursorVisible)

    // Scrolls the list so the keyboard-selected row shows, a row clear of the
    // faded edges.
    function ensureCursorVisible() {
        if (!opened || cursor < 0 || cursor >= lines.length) return
        var y = (cursor % perColumn) * lineHeight
        var margin = Math.min(lineHeight, Math.max(0, (flick.height - lineHeight) / 2))
        var maxY = Math.max(0, flick.contentHeight - flick.height)
        if (y - margin < flick.contentY) flick.contentY = Math.max(0, y - margin)
        else if (y + lineHeight + margin > flick.contentY + flick.height)
            flick.contentY = Math.min(maxY, y + lineHeight + margin - flick.height)
    }
    onQueryChanged: { hoverKey = ""; hoverIndex = -1 }

    // Full text of the active row when it is cut off, in page coordinates:
    // under the row, or above it (`above`) when there is no room below.
    // Derived from the state, so it follows scrolling and reused rows.
    readonly property var tip: {
        var i = activeIndex
        if (!opened || i < 0 || !activeLine) return null
        if (comboMeasure.advanceWidth <= rowComboWidth && descMeasure.advanceWidth <= columnWidth - rowComboWidth) return null
        var rowY = flick.y + (i % perColumn) * lineHeight - flick.contentY
        if (rowY + lineHeight / 2 < flick.y || rowY + lineHeight / 2 > flick.y + flick.height) return null
        return { combo: activeLine.combo, text: activeLine.text,
                 x: flick.x + list.x + Math.floor(i / perColumn) * columnStep,
                 y: rowY + lineHeight + Style.space(4), above: rowY - Style.space(4) }
    }

    TextMetrics {
        id: comboMeasure
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.weight: Font.Medium
        text: root.activeLine ? root.activeLine.combo : ""
    }

    TextMetrics {
        id: descMeasure
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        text: root.activeLine ? root.activeLine.text : ""
    }


    FontMetrics {
        id: metrics
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
    }

    // Failures are shown, not hidden behind an empty or stale map.
    function failed(what, stderr) {
        var reason = String(stderr || "").trim().split("\n").pop()
        loadError = what + (reason ? ": " + reason : "")
    }

    Process {
        id: records
        command: [root.helper]
        stdout: StdioCollector { id: recordsOut; waitForEnd: true }
        stderr: StdioCollector { id: recordsErr; waitForEnd: true }
        onExited: function(code) {
            var text = recordsOut.text
            var parsed = Model.parse(text)
            // Unchanged bindings are not handed on again, so the open page
            // does not rebuild.
            if (code === 0 && parsed.length) {
                if (text !== root.recordsText) { root.recordsText = text; root.rawBindings = parsed }
            } else root.failed("Could not read the keybindings", recordsErr.text)
            root.loaded = true
            if (!layoutProc.running) loadTimeout.stop()
        }
    }

    Process {
        id: layoutProc
        command: [root.helper, "keys"]
        stdout: StdioCollector { id: layoutOut; waitForEnd: true }
        stderr: StdioCollector { id: layoutErr; waitForEnd: true }
        onExited: function(code) {
            var text = layoutOut.text
            var parsed = Model.parseLayout(text)
            if (code === 0 && parsed.layout && Object.keys(parsed.keys).length) {
                if (text !== root.layoutText) { root.layoutText = text; root.layout = parsed }
                root.universalCount = parsed.universal
            } else root.failed("Could not read the keyboard layout", layoutErr.text)
            root.layoutDone = true
            root.layoutRead = true
            if (!records.running) loadTimeout.stop()
        }
    }

    Timer {
        id: loadTimeout
        interval: 8000
        onTriggered: {
            if (records.running) { records.running = false; root.failed("Reading the keybindings timed out", "") }
            if (layoutProc.running) { layoutProc.running = false; root.layoutDone = true; root.layoutRead = true; root.failed("Reading the keyboard layout timed out", "") }
        }
    }

    // Is Hyprland in the key map's submap? Asked once the layer has opened,
    // then followed live through Hyprland's submap events.
    Timer { id: guardCheck; interval: 350; onTriggered: root.askGuard() }

    // Bumped at each opening and each submap event: an answer counts only if
    // nothing newer has happened since it was asked.
    property int guardSerial: 0
    property int guardAsked: -1
    property bool guardAgain: false
    function askGuard() {
        if (submapProc.running) { guardAgain = true; return }
        guardAsked = guardSerial
        submapProc.running = true
    }

    Process {
        id: submapProc
        command: ["hyprctl", "submap"]
        stdout: StdioCollector { id: submapOut; waitForEnd: true }
        onExited: function(code) {
            if (root.guardAgain) { root.guardAgain = false; root.askGuard(); return }
            if (!root.opened || root.guardAsked !== root.guardSerial) return   // overtaken
            root.guarded = code === 0 && submapOut.text.trim() === root.submapName
            root.guardChecked = true
        }
    }

    // Only while open: Hyprland sends raw events all the time.
    Connections {
        target: root.opened ? Hyprland : null
        function onRawEvent(event) {
            if (event.name !== "submap") return
            root.guardSerial++
            root.guarded = String(event.data).trim() === root.submapName
            root.guardChecked = true
            if (!root.guarded) root.clearPin()
        }
    }

    Process {
        id: statusProc
        command: [root.helper, "status"]
        stdout: StdioCollector { id: statusOut; waitForEnd: true }
        stderr: StdioCollector { id: statusErr; waitForEnd: true }
        onExited: function(code) {
            if (code === 0) root.setupState = statusOut.text.trim()
            else {
                root.setupState = ""
                root.failed("Could not check the setup", statusErr.text)
            }
        }
    }

    // One-click setup: only on the user's click, adds one line to
    // ~/.config/hypr/bindings.lua (see `extended-keybindings-viewer setup`).
    Process {
        id: setupProc
        command: [root.helper, "setup"]
        stdout: StdioCollector { id: setupOut; waitForEnd: true }
        stderr: StdioCollector { id: setupErr; waitForEnd: true }
        onExited: function(code) {
            root.settingUp = false
            if (code !== 0) root.failed("Setup failed", setupErr.text)
            else root.setupState = setupOut.text.trim()
            guardCheck.restart()
        }
    }

    // Optional: ~/.config/omarchy/extensions/extended-keybindings-viewer.json,
    // {"shape": "iso" | "ansi"} for a keyboard whose shape the layout does not
    // tell, and {"fullscreen": true}, written by the fullscreen button.
    readonly property string settingsDirPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/extensions"

    FileView {
        id: settingsFile
        path: root.settingsDirPath + "/extended-keybindings-viewer.json"
        printErrors: false
        atomicWrites: true
        onLoaded: {
            var parsed = null
            try { parsed = JSON.parse(text()) } catch (e) {}
            root.applySettings(parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null)
        }
        // Created on the first toggle only when there is no file yet.
        onLoadFailed: function(error) { root.applySettings(error === FileViewError.FileNotFound ? {} : null) }
        onSaveFailed: root.failed("Could not save the fullscreen setting", "")
        // A toggle made while writing (its reload was skipped) is saved now.
        onSaved: if (root.saveWanted) reload()
    }

    Process {
        id: settingsDir
        command: ["mkdir", "-p", root.settingsDirPath]
        onExited: function(code) {
            if (code === 0) settingsFile.setText(root.settingsOut)
            else root.failed("Could not save the fullscreen setting", "")
        }
    }

    // Test commands below work only while this file exists; it is checked on
    // every call (synchronously), so removing it switches them off at once.
    FileView {
        id: testFlag
        path: Quickshell.env("XDG_RUNTIME_DIR") ? Quickshell.env("XDG_RUNTIME_DIR") + "/io.github.erikrjohansson.extended-keybindings-viewer-test" : ""
        blockLoading: true
        printErrors: false
        onLoaded: root.testHooks = true
        onLoadFailed: root.testHooks = false
    }

    function testAllowed() {
        if (!testFlag.path) return false
        testHooks = false
        testFlag.reload()
        testFlag.waitForJob()   // reload is asynchronous; wait for its answer
        return testHooks
    }

    IpcHandler {
        target: "io.github.erikrjohansson.extended-keybindings-viewer"
        function status(): string {
            return JSON.stringify({ opened: root.opened, loaded: root.loaded, error: root.loadError,
                guarded: root.guarded, setup: root.setupState, bindings: root.bindings.length,
                layout: root.layout.layout, iso: root.iso, activeMods: root.activeMods, held: root.heldMods,
                query: root.query, lines: root.lines.length, cursor: root.cursor,
                line: root.activeLine ? root.activeLine.combo + " " + root.activeLine.text : "", lit: root.lit,
                typing: root.typing, inList: root.inList, scrollY: Math.round(flick.contentY) })
        }
    }

    IpcHandler {
        target: "io.github.erikrjohansson.extended-keybindings-viewer-test"
        enabled: root.testHooks
        function setQuery(text: string): void { if (root.testAllowed()) root.query = text }
        function press(combo: string): void {
            if (!root.testAllowed()) return
            var parts = combo.split(/[ +]+/)
            root.pin(parts.slice(0, -1).map(function(m) { return m.toUpperCase() }), parts[parts.length - 1])
        }
        function setMods(mods: string): void { if (root.testAllowed()) root.baseMods = mods ? mods.toUpperCase().split(/[ +,]+/) : [] }
        function hold(mods: string): void { if (root.testAllowed()) root.heldMods = mods ? mods.toUpperCase().split(/[ +,]+/) : [] }
        function move(step: int): void { if (root.testAllowed()) root.move(step) }
        function hover(key: string): void { if (root.testAllowed()) root.hoverKey = key }
        function scrollTo(y: int): void { if (root.testAllowed()) flick.contentY = y }
    }

    PanelWindow {
        id: panel
        screen: root.targetScreen
        visible: root.opened && root.ready
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omarchy-extended-keybindings-viewer"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        // The submap is entered when the layer maps, so it is checked from then.
        onVisibleChanged: if (visible) {
            if (!root.typing) keyCatcher.forceActiveFocus()
            guardCheck.restart()
        }

        // Windowed, the desktop shows dimmed around the card, as with Omarchy's menus.
        Rectangle {
            anchors.fill: parent
            color: root.fullscreen ? Color.menu.background : Color.menu.scrim
        }

        // Clicks never close the key map (Esc and SUPER + K do); outside the
        // page they just leave the search or the list.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: {
                if (root.typing) root.stopSearch()
                else if (root.inList) root.leaveList(false)
            }
        }

        Ui.BorderSurface {
            id: frame
            readonly property real inset: root.fullscreen ? 0 : root.cardInset
            anchors.centerIn: parent
            width: root.fullscreen ? parent.width : root.contentWidth + 2 * inset
            height: root.fullscreen ? parent.height : root.cardHeight
            radius: root.fullscreen ? 0 : Style.cornerRadius
            color: root.fullscreen ? "transparent" : Color.menu.background
            borderSpec: root.fullscreen ? Border.none()
                : Border.surfaceSpec("menu", "border", Color.menu.border, root.cardBorder)

            // Fullscreen ↔ windowed, in the frame's top right corner.
            Rectangle {
                id: sizeButton
                readonly property real size: Math.round(Style.font.heading * 2.2)
                readonly property real margin: root.fullscreen ? Style.space(24) : (frame.inset - size) / 2 + Style.space(4)
                x: frame.width - size - Math.max(Style.space(8), margin)
                y: Math.max(Style.space(8), margin)
                z: 3
                width: size
                height: size
                radius: root.radius
                color: sizeArea.containsMouse ? Util.alpha(root.fg, 0.08) : "transparent"
                border.width: 1
                border.color: Util.alpha(root.fg, sizeArea.containsMouse ? 0.5 : 0)

                Text {
                    anchors.centerIn: parent
                    text: root.fullscreen ? "󰊔" : "󰊓"
                    font.pixelSize: Math.round(Style.font.heading * 1.3)
                    color: Util.alpha(root.fg, sizeArea.containsMouse ? 0.92 : 0.66)
                }

                MouseArea {
                    id: sizeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleFullscreen()
                }
            }

            Item {
                id: page
                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: root.fullscreen ? Math.max(Style.space(40), parent.height * 0.06) : frame.inset
                anchors.bottomMargin: root.fullscreen ? Style.space(32) : frame.inset

                // Clicks inside the page should not close it; they leave the search.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: {
                        if (root.typing) root.stopSearch()
                        else if (root.inList) root.leaveList(false)
                    }
                }

                // Outside the search box every key press is a shortcut to look up:
                // modifiers filter while held, a full combination shows while pressed.
                Item {
                    id: keyCatcher
                    focus: true
                    Keys.onPressed: function(event) {
                        root.syncMods(event, true)
                        event.accepted = true
                        if (root.modForEvent(event)) {
                            if (!event.isAutoRepeat) root.clearPin()
                            return
                        }
                        if (root.navigate(event)) return
                        var plain = root.heldMods.length === 0
                        var name = root.layout.codes[event.nativeScanCode] || ""
                        if (root.inList && plain) {
                            if (event.key === Qt.Key_Escape) { root.leaveList(true); return }
                            if (event.key === Qt.Key_Down) { root.move(1); return }
                            if (event.key === Qt.Key_Up) { root.move(-1); return }
                            if (event.key === Qt.Key_Left) { root.moveColumn(-1); return }
                            if (event.key === Qt.Key_Right) { root.moveColumn(1); return }
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) return
                            root.leaveList(false)
                        }
                        if (plain && event.key === Qt.Key_Escape) {
                            if (root.pinned) root.clearPin()
                            else if (root.searching) root.query = ""
                            else root.dismiss()
                            return
                        }
                        if (name) root.pin(root.heldMods, name)
                    }
                    Keys.onReleased: function(event) {
                        root.syncMods(event, false)
                        event.accepted = true
                        if (!event.isAutoRepeat && root.pinned && root.layout.codes[event.nativeScanCode] === root.pinnedKey)
                            root.clearPin()
                    }
                    onActiveFocusChanged: if (!activeFocus && !root.typing) root.heldMods = []
                }

                Item {
                    id: header
                    width: parent.width
                    height: title.implicitHeight

                    Text {
                        id: title
                        text: "Keybindings"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.displayLarge
                        font.weight: Font.Medium
                        color: root.fg
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.modFilter || root.pinned
                        textFormat: Text.PlainText
                        text: root.pinned ? root.pinnedCombo : root.activeMods.join(" + ")
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.heading
                        font.weight: Font.Medium
                        color: root.accent
                    }
                }

                Keyboard {
                    id: keyboard
                    anchors.top: header.bottom
                    // The three gaps (title–keyboard, keyboard–search, hint–list)
                    // look equal; the margins differ by what each edge's own
                    // inset adds (key gaps, line spacing).
                    anchors.topMargin: root.unit * 0.77
                    anchors.horizontalCenter: parent.horizontalCenter
                    unit: root.unit
                    iso: root.iso
                    layoutKeys: root.layout.keys
                    chars: root.layout.chars
                    activeMods: root.shownMods
                    lit: root.lit
                    bound: root.boundKeys
                    hoverKey: root.hoverKey
                    fontFamily: root.fontFamily
                    fg: root.fg
                    accent: root.accent
                    base: Color.menu.background
                    pointerArmed: root.pointerArmed
                    onKeyHovered: function(id) { root.hoverKey = id }
                    onKeyClicked: function(id) { root.selectKey(id) }
                    onPartPressed: function(id) { root.pressPart(id) }
                    onPartReleased: function(id) { root.releasePart(id) }
                }

                Rectangle {
                    id: searchBox
                    anchors.top: keyboard.bottom
                    anchors.topMargin: root.unit * 0.8
                    // One list column wide, centred: a single column of results
                    // sits right under it, and with three columns it is the middle one.
                    x: (parent.width - width) / 2
                    width: root.columnWidth
                    height: Math.round(root.unit * 0.8)
                    radius: root.radius
                    color: Util.alpha(root.fg, 0.04)
                    border.width: 1
                    border.color: root.typing ? Util.alpha(root.accent, 0.8) : Util.alpha(root.fg, 0.22)

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        onClicked: root.startSearch()
                    }

                    Text {
                        id: searchIcon
                        anchors.left: parent.left
                        anchors.leftMargin: root.unit * 0.3
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰍉"
                        font.pixelSize: Style.font.heading
                        color: root.typing ? root.accent : Util.alpha(root.fg, 0.55)
                    }

                    TextInput {
                        id: search
                        anchors.left: searchIcon.right
                        anchors.leftMargin: root.unit * 0.2
                        anchors.right: parent.right
                        anchors.rightMargin: root.unit * 0.3
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.query
                        color: root.fg
                        selectionColor: Util.alpha(root.accent, 0.4)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                        clip: true
                        onTextEdited: root.query = text
                        onActiveFocusChanged: root.typing = activeFocus
                        Keys.onPressed: function(event) {
                            root.syncMods(event, true)
                            if (root.modForEvent(event)) return
                            if (root.navigate(event)) {}
                            else if (event.key === Qt.Key_Escape) root.stopSearch()
                            else if (event.key === Qt.Key_Down) root.nextPlace()
                            else if (event.key === Qt.Key_Up) {}
                            else return
                            event.accepted = true
                        }
                        Keys.onReleased: function(event) { root.syncMods(event, false) }

                        Text {
                            visible: !search.text
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search   ·   Ctrl+F"
                            font: search.font
                            color: Util.alpha(root.fg, 0.6)
                        }
                    }
                }

                // Messages under the search box: an error (always shown), the setup
                // notice or the hint, and the universal-shortcut warning.
                Column {
                    id: messages
                    anchors.top: searchBox.bottom
                    anchors.topMargin: root.unit * 0.3
                    width: parent.width
                    spacing: Style.space(8)

                    Text {
                        width: parent.width
                        visible: root.loadError !== ""
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        text: root.loadError
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        color: Color.urgent
                    }

                    Item {
                        width: parent.width
                        height: notice.visible ? notice.height : hint.height

                        Text {
                            id: hint
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: !notice.visible
                            // The short wording when the full one does not fit: one
                            // line either way, so the list never moves.
                            readonly property var texts: !root.loaded ? ["reading keybindings…", ""]
                                : root.typing ? ["type to search   ·   ctrl+tab to move between keyboard, search and list   ·   esc back to the keyboard",
                                                 "type to search   ·   ctrl+tab next place   ·   esc back"]
                                : root.inList ? ["←↑↓→ to browse   ·   ctrl+tab to move between keyboard, search and list   ·   esc " + (root.searching ? "back to the search" : "back to the keyboard"),
                                                 "←↑↓→ to browse   ·   ctrl+tab next place   ·   esc back"]
                                : root.pinned && !root.pinnedExact && root.lines.length
                                  ? [root.pinnedCombo + " is not bound on its own   ·   bindings that use it:", root.pinnedCombo + " alone is not bound:"]
                                : ["press a shortcut to see what it does   ·   hold modifiers to filter   ·   ctrl+tab to move between keyboard, search and list   ·   ctrl+shift+f fullscreen   ·   esc closes",
                                   "press a shortcut   ·   hold modifiers to filter   ·   ctrl+tab next place   ·   ctrl+shift+f fullscreen   ·   esc closes"]
                            width: Math.min(implicitWidth, parent.width)
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            text: texts[1] && hintMeasure.advanceWidth > parent.width ? texts[1] : texts[0]
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            color: Util.alpha(root.fg, 0.66)
                        }

                        // Without the submap, pressing a shortcut here would run it: lookups
                        // stay off and this explains why (and offers the one-click setup).
                        TextMetrics {
                            id: hintMeasure
                            font: hint.font
                            text: hint.texts[0]
                        }

                        Row {
                            id: notice
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Style.space(16)
                            visible: root.guardChecked && !root.guarded && root.loaded

                            // Wraps when the card is too narrow for one line.
                            Text {
                                id: noticeText
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(noticeMeasure.advanceWidth + 1,
                                                notice.parent.width - (setupButton.visible ? setupButton.width + notice.spacing : 0))
                                wrapMode: Text.WordWrap
                                textFormat: Text.PlainText
                                text: root.setupState === "setup"
                                    ? "Shortcuts are not paused, so looking them up is off. Reload Hyprland to finish the setup."
                                    : "Shortcuts are not paused, so looking them up is off. Set up SUPER + K to open Extended Keybindings Viewer:"
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                color: Util.alpha(root.fg, 0.75)
                            }

                            TextMetrics {
                                id: noticeMeasure
                                font: noticeText.font
                                text: noticeText.text
                            }

                            Ui.Button {
                                id: setupButton
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.setupState !== "setup"
                                enabled: !root.settingUp
                                text: root.settingUp ? "Setting up…" : "Set up"
                                onClicked: {
                                    root.settingUp = true
                                    root.loadError = ""
                                    setupProc.running = true
                                }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        visible: root.universalWarning !== "" && root.guarded && root.layoutDone
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        text: root.universalWarning
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        color: Color.urgent
                    }
                }

                Flickable {
                    id: flick
                    // Saved once the change has settled: while a lookup starts, the
                    // derived `baseView` can still read true for a moment.
                    onHeightChanged: Qt.callLater(root.ensureCursorVisible)
                    onContentYChanged: Qt.callLater(function() {
                        if (root.baseView && !root.restoring) root.baseY = flick.contentY
                    })
                    anchors.top: messages.bottom
                    anchors.topMargin: root.unit * 0.73
                    anchors.bottom: parent.bottom
                    // Wider than the page by the row padding, so a selected row's
                    // highlight can reach past text aligned with the page edges.
                    x: -root.rowPad
                    width: parent.width + 2 * root.rowPad
                    clip: true
                    contentHeight: list.height
                    boundsBehavior: Flickable.StopAtBounds

                    Item {
                        id: list
                        x: root.rowPad + root.listOffset
                        width: (root.cols.length - 1) * root.columnStep + root.columnWidth
                        height: root.lines.length ? root.perColumn * root.lineHeight : 0

                        // One fixed set of rows, reused by every view: building
                        // the rows anew on each key press took ~100 ms, so fast
                        // typing fell behind.
                        // The theme's selected-row look, border spec included, as in
                        // Omarchy's menu: one, moved to the active row.
                        Ui.BorderSurface {
                            visible: root.activeIndex >= 0
                            x: Math.floor(root.activeIndex / root.perColumn) * root.columnStep - root.rowPad
                            y: (root.activeIndex % root.perColumn) * root.lineHeight
                            width: root.columnWidth + 2 * root.rowPad
                            height: root.lineHeight
                            radius: root.radius
                            color: root.selectedFill
                            borderSpec: Border.surfaceSpec("menu", "selected-border", root.selectedBorder, 0)
                        }

                        Repeater {
                            model: root.slotCount
                            delegate: Line {}
                        }
                    }
                }

                // Soft edges where the list scrolls on past the view.
                Rectangle {
                    anchors.top: flick.top
                    x: flick.x
                    width: flick.width
                    height: Style.space(28)
                    visible: flick.contentY > 1
                    gradient: Gradient {
                        GradientStop { position: 0; color: Color.menu.background }
                        GradientStop { position: 1; color: Util.alpha(Color.menu.background, 0) }
                    }
                }

                Rectangle {
                    anchors.bottom: flick.bottom
                    x: flick.x
                    width: flick.width
                    height: Style.space(40)
                    visible: flick.contentY + flick.height < flick.contentHeight - 1
                    gradient: Gradient {
                        GradientStop { position: 0; color: Util.alpha(Color.menu.background, 0) }
                        GradientStop { position: 1; color: Color.menu.background }
                    }
                }

                // Full text of a row that does not fit its column.
                Rectangle {
                    visible: root.tip !== null
                    x: root.tip ? Math.max(0, Math.min(root.tip.x, page.width - width)) : 0
                    y: !root.tip ? 0 : root.tip.y + height <= page.height ? root.tip.y
                                     : Math.max(0, root.tip.above - height)
                    z: 2
                    width: Math.min(tipMeasure.width + Style.space(20), page.width * 0.6)
                    height: Math.min(tipText.implicitHeight + Style.space(12), page.height * 0.3)
                    clip: true

                    TextMetrics {
                        id: tipMeasure
                        font: tipText.font
                        text: tipText.text
                    }
                    radius: root.radius
                    color: Color.tooltip.background
                    border.width: 1
                    border.color: Color.tooltip.border

                    Text {
                        id: tipText
                        anchors.centerIn: parent
                        width: parent.width - Style.space(20)
                        wrapMode: Text.Wrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: root.tip ? root.tip.combo + "   " + root.tip.text : ""
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        color: Color.tooltip.text
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: flick.top
                    visible: root.loaded && !root.lines.length && !root.loadError
                    textFormat: Text.PlainText
                    text: root.pinned ? "No binding uses " + root.pinnedCombo
                        : root.searching ? "Nothing matches “" + root.query + "”"
                        : "No keybindings for " + (root.activeMods.length ? root.activeMods.join(" + ") : "keys without a modifier")
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    color: Util.alpha(root.fg, 0.6)
                }
            }
        }

        HoverHandler {
            onPointChanged: root.pointerAt(point.position)
        }

        // On top of everything: clicks and scrolls that are lookups are taken
        // here, every other one passes through to the page below.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: function(mouse) { mouse.accepted = root.pressButton(mouse) }
            onReleased: function(mouse) { root.releaseButton(mouse) }
            onWheel: function(wheel) { wheel.accepted = root.scrollLookup(wheel) }
        }
    }

    // A row slot: shows lines[index], placed by column, hidden when the
    // current view is shorter.
    component Line: Item {
        id: line
        required property int index
        readonly property int at: index
        readonly property var row: root.rowAt(index, root.lines, flick.contentY, flick.height)
        readonly property bool shown: row !== null
        readonly property bool near: shown && row.near
        readonly property bool active: shown && root.activeIndex === at
        visible: shown
        x: shown ? row.x : 0
        y: shown ? row.y : 0
        width: root.columnWidth
        height: root.lineHeight

        Text {
            id: comboText
            width: root.rowComboWidth
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: line.near ? line.row.line.combo : ""
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.weight: Font.Medium
            color: line.active ? root.accent : root.fg
        }

        Text {
            id: descText
            anchors.left: comboText.right
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: line.near ? line.row.line.text : ""
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            color: line.active ? root.accent : Util.alpha(root.fg, 0.78)
        }

        MouseArea {
            id: lineArea
            anchors.fill: parent
            anchors.leftMargin: -root.rowPad
            anchors.rightMargin: -root.rowPad
            hoverEnabled: true
            onClicked: root.enterList(line.at)
        }

        readonly property bool pointed: root.pointerArmed && lineArea.containsMouse
        onPointedChanged: {
            if (pointed) root.hoverIndex = at
            else if (root.hoverIndex === at) root.hoverIndex = -1
        }
    }
}
