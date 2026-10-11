import QtQuick
import QtQuick.Shapes
import qs.Commons

// The keyboard, drawn by XKB key name (AE01, AC10, LFSH, …) in key units,
// ANSI or ISO, labelled from the active layout. Modifier keys are identified
// by what the layout puts on them, so both halves of a modifier light as one.
Item {
    id: keyboard

    property real unit: 48
    property bool iso: false
    property var layoutKeys: ({})     // XKB name → [level1, level2] keysyms
    property var chars: ({})          // keysym → the character it types
    property var activeMods: []       // modifiers of the current filter
    property var lit: []              // modifiers + key names of the line looked at
    property var bound: ({})          // key name → true when it has a binding
    property string hoverKey: ""
    property bool pointerArmed: true   // false while the pointer has not moved
    property string fontFamily: Style.font.family
    property color accent: Color.accent
    property color fg: Color.foreground
    property color base: Color.background

    signal keyHovered(string id)
    signal keyClicked(string id)
    signal partPressed(string id)     // a drawn mouse part pressed / released
    signal partReleased(string id)

    // Keyboard 18.5 units wide, then the mouse.
    readonly property real mouseX: 19.5      // one unit after the arrows, as ESC to F1
    readonly property real mouseWidth: 2.6
    readonly property real units: mouseX + mouseWidth
    width: unit * units
    height: unit * 6.25

    function row(y, x, keys) {
        var out = []
        for (var i = 0; i < keys.length; ++i) {
            var k = keys[i]
            if (typeof k === "number") { x += k; continue }
            var w = k.length > 1 ? k[1] : 1
            out.push({ name: k[0], x: x, y: y, w: w })
            x += w
        }
        return out
    }

    function names(prefix, from, to) {
        var out = []
        for (var i = from; i <= to; ++i) out.push([prefix + (i < 10 ? "0" : "") + i])
        return out
    }

    readonly property var keys: {
        var top = row(0, 0, [["ESC"], 1].concat(names("FK", 1, 4), [0.5], names("FK", 5, 8), [0.5],
                                                names("FK", 9, 12), [0.5, ["PRSC"], ["HOME"], ["DELE"]]))
        var numbers = row(1.25, 0, [["TLDE"]].concat(names("AE", 1, 12), [["BKSP", 2]]))
        var bottom = row(5.25, 0, [["LCTL", 1.25], ["LWIN", 1.25], ["LALT", 1.25], ["SPCE", 6.25],
                                   ["RALT", 1.25], ["RWIN", 1.25], ["COMP", 1.25], ["RCTL", 1.25], 0.5,
                                   ["LEFT"], ["DOWN"], ["RGHT"]])
        var rows = iso ? [].concat(
            row(2.25, 0, [["TAB", 1.5]].concat(names("AD", 1, 12))),
            [{ name: "RTRN", x: 13.5, y: 2.25, w: 1.5, h: 2, shape: "iso-enter" }],
            row(3.25, 0, [["CAPS", 1.75]].concat(names("AC", 1, 11), [["BKSL"]])),
            row(4.25, 0, [["LFSH", 1.25], ["LSGT"]].concat(names("AB", 1, 10), [["RTSH", 2.75], 1.5, ["UP"]])))
        : [].concat(
            row(2.25, 0, [["TAB", 1.5]].concat(names("AD", 1, 12), [["BKSL", 1.5]])),
            row(3.25, 0, [["CAPS", 1.75]].concat(names("AC", 1, 11), [["RTRN", 2.25]])),
            row(4.25, 0, [["LFSH", 2.25]].concat(names("AB", 1, 10), [["RTSH", 2.75], 1.5, ["UP"]])))
        return [].concat(top, numbers, rows, bottom)
    }

    readonly property var keyNames: keys.map(function(k) { return k.name })

    // Fixed labels for keys that do not type a character.
    readonly property var fixedLabels: ({
        "ESC": "ESC", "TAB": "TAB", "BKSP": "BKSP", "RTRN": "RETURN", "SPCE": "",
        "LFSH": "SHIFT", "RTSH": "SHIFT", "LCTL": "CTRL", "RCTL": "CTRL", "LWIN": "SUPER",
        "RWIN": "SUPER", "LALT": "ALT", "COMP": "MENU", "PRSC": "PRT", "HOME": "HOME",
        "DELE": "DEL", "LEFT": "←", "RGHT": "→", "UP": "↑", "DOWN": "↓",
        "BTN_LEFT": "LEFT MOUSE", "BTN_RIGHT": "RIGHT MOUSE", "BTN_MIDDLE": "MIDDLE MOUSE",
        "BTN_SIDE": "BACK MOUSE", "BTN_EXTRA": "FORWARD MOUSE",
        "WHEEL_UP": "SCROLL ↑", "WHEEL_DOWN": "SCROLL ↓", "WHEEL_LEFT": "SCROLL ←", "WHEEL_RIGHT": "SCROLL →"
    })

    // Keys whose label follows what the layout puts on them, so swapped or
    // remapped keys (ctrl:swapcaps, compose:caps, AltGr) read correctly.
    readonly property var roleKeys: ["CAPS", "LFSH", "RTSH", "LCTL", "RCTL", "LWIN", "RWIN", "LALT", "RALT", "ESC", "TAB", "BKSP", "RTRN"]

    function roleLabel(sym) {
        if (/^Shift_/.test(sym)) return "SHIFT"
        if (/^Control_/.test(sym)) return "CTRL"
        if (/^(Super_|Hyper_)/.test(sym)) return "SUPER"
        if (/^(Alt_|Meta_)/.test(sym)) return "ALT"
        if (sym === "ISO_Level3_Shift" || sym === "Mode_switch") return "ALT GR"
        if (sym === "Caps_Lock") return "CAPS"
        if (sym === "Multi_key") return "COMPOSE"
        if (sym === "Escape") return "ESC"
        if (sym === "Tab" || sym === "ISO_Left_Tab") return "TAB"
        if (sym === "BackSpace") return "BKSP"
        if (sym === "Return") return "RETURN"
        return ""
    }

    readonly property var symbolChars: ({
        "plus": "+", "minus": "-", "equal": "=", "comma": ",", "period": ".", "slash": "/",
        "backslash": "\\", "semicolon": ";", "colon": ":", "apostrophe": "'", "quotedbl": "\"",
        "grave": "`", "asciitilde": "~", "exclam": "!", "at": "@", "numbersign": "#",
        "dollar": "$", "percent": "%", "asciicircum": "^", "ampersand": "&", "asterisk": "*",
        "parenleft": "(", "parenright": ")", "underscore": "_", "bracketleft": "[",
        "bracketright": "]", "braceleft": "{", "braceright": "}", "bar": "|", "less": "<",
        "greater": ">", "question": "?", "section": "§", "onehalf": "½", "degree": "°",
        "sterling": "£", "currency": "¤", "EuroSign": "€", "notsign": "¬", "mu": "µ",
        "ssharp": "ß", "ae": "æ", "AE": "Æ", "oslash": "ø", "Oslash": "Ø", "Ooblique": "Ø",
        "eth": "ð", "ETH": "Ð", "thorn": "þ", "THORN": "Þ", "masculine": "º", "ordfeminine": "ª",
        "exclamdown": "¡", "questiondown": "¿", "guillemotleft": "«", "guillemotright": "»",
        "acute": "´", "diaeresis": "¨", "cedilla": "¸", "twosuperior": "²", "threesuperior": "³",
        "paragraph": "¶", "multiply": "×", "division": "÷", "periodcentered": "·",
        "plusminus": "±", "brokenbar": "¦", "dead_acute": "´", "dead_grave": "`",
        "dead_diaeresis": "¨", "dead_circumflex": "^", "dead_tilde": "~", "dead_caron": "ˇ",
        "dead_cedilla": "¸", "dead_abovering": "°", "dead_ogonek": "˛", "dead_breve": "˘"
    })

    readonly property var marks: ({
        "acute": "́", "grave": "̀", "circumflex": "̂", "diaeresis": "̈",
        "tilde": "̃", "ring": "̊", "cedilla": "̧", "caron": "̌",
        "abovedot": "̇", "ogonek": "̨", "breve": "̆", "macron": "̄"
    })

    function symChar(sym) {
        if (!sym) return ""
        if (sym.length === 1) return sym
        if (symbolChars[sym] !== undefined) return symbolChars[sym]
        if (chars[sym] !== undefined) return chars[sym]
        var m = sym.match(/^([A-Za-z])(acute|grave|circumflex|diaeresis|tilde|ring|cedilla|caron|abovedot|ogonek|breve|macron)$/)
        if (m) return (m[1] + marks[m[2]]).normalize("NFC")
        return ""
    }

    function modOf(name) {
        var sym = (layoutKeys[name] || [""])[0]
        if (/^Shift_/.test(sym)) return "SHIFT"
        if (/^Control_/.test(sym)) return "CTRL"
        if (/^(Alt_|Meta_)/.test(sym)) return "ALT"
        if (/^(Super_|Hyper_)/.test(sym)) return "SUPER"
        return ""
    }

    function labels(name) {
        var syms = layoutKeys[name] || ["", ""]
        if (roleKeys.indexOf(name) !== -1) {
            var role = roleLabel(syms[0])
            if (role) return [role, ""]
            var typed = symChar(syms[0])
            if (typed) return [typed.toUpperCase(), ""]
        }
        if (/^FK\d\d$/.test(name)) return ["F" + Number(name.slice(2)), ""]
        if (fixedLabels[name] !== undefined) return [fixedLabels[name], ""]
        var base = symChar(syms[0]).toUpperCase()
        var shifted = symChar(syms[1])
        return [base, shifted && shifted !== base ? shifted : ""]
    }

    // Whether a point (in the keyboard's coordinates) is on a key or a part of
    // the drawn mouse; the gaps between them and the mouse's body are not.
    function controlAt(x, y) {
        var item = childAt(x, y)
        if (!item) return false
        // The empty corner left of ISO Enter's lower half.
        if (item.modelData && item.modelData.shape === "iso-enter")
            return !(x - item.x < unit * 0.25 && y - item.y > unit - item.gap)
        if (item !== mouse) return true
        var part = mouse.childAt(x - mouse.x, y - mouse.y)
        return !!part && !!part.partId
    }

    // States shared by keys and mouse parts.
    function partFill(id, inLayer) {
        return inLayer ? Util.alpha(accent, 0.32)
             : lit.indexOf(id) !== -1 ? Util.alpha(accent, 0.32)
             : Util.alpha(fg, bound[id] === true ? 0.035 : 0.015)
    }
    function partEdge(id, inLayer) {
        return inLayer || lit.indexOf(id) !== -1 ? accent
             : Util.alpha(fg, hoverKey === id ? 0.8 : bound[id] === true ? 0.5 : 0.13)
    }
    function partInk(id) {
        return lit.indexOf(id) !== -1 ? accent : Util.alpha(fg, bound[id] === true ? 0.92 : 0.32)
    }

    // The mouse: two buttons over a rounded body, the wheel between them with
    // scroll arrows above and below it.
    Item {
        id: mouse
        readonly property real u: keyboard.unit
        readonly property real gap: u * 0.09
        readonly property real half: (width - gap) / 2
        readonly property real buttonHeight: u * 1.7
        // Body and buttons share their top corners so the outlines meet.
        readonly property real topRadius: Math.min(half, buttonHeight) / 2
        // Spans the main block from the number row to the bottom row.
        x: keyboard.mouseX * u + gap / 2
        y: u * 1.25 + gap / 2
        width: keyboard.mouseWidth * u - gap
        height: u * 5 - gap

        Rectangle {
            anchors.fill: parent
            topLeftRadius: mouse.topRadius
            topRightRadius: mouse.topRadius
            bottomLeftRadius: width / 2
            bottomRightRadius: width / 2
            color: Util.alpha(keyboard.fg, 0.015)
            border.width: 1
            border.color: Util.alpha(keyboard.fg, 0.13)
        }

        component Part: Rectangle {
            id: part
            property string partId: ""
            property string label: ""
            color: keyboard.partFill(partId, false)
            border.width: keyboard.lit.indexOf(partId) !== -1 ? 1.5 : 1
            border.color: keyboard.partEdge(partId, false)

            Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: part.label
                font.family: keyboard.fontFamily
                font.pixelSize: Math.round(keyboard.unit * 0.22)
                color: keyboard.partInk(part.partId)
            }

            MouseArea {
                id: partArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                onPressed: keyboard.partPressed(part.partId)
                onReleased: keyboard.partReleased(part.partId)
                onCanceled: keyboard.partReleased(part.partId)
            }

            readonly property bool pointed: keyboard.pointerArmed && partArea.containsMouse
            onPointedChanged: {
                if (pointed) keyboard.keyHovered(partId)
                else if (keyboard.hoverKey === partId) keyboard.keyHovered("")
            }
        }

        Part {
            partId: "BTN_LEFT"
            width: mouse.half
            height: mouse.buttonHeight
            topLeftRadius: mouse.topRadius
            bottomLeftRadius: mouse.gap
            topRightRadius: mouse.gap
            bottomRightRadius: mouse.gap
        }

        Part {
            partId: "BTN_RIGHT"
            x: mouse.half + mouse.gap
            width: mouse.half
            height: mouse.buttonHeight
            topRightRadius: mouse.topRadius
            topLeftRadius: mouse.gap
            bottomLeftRadius: mouse.gap
            bottomRightRadius: mouse.gap
        }

        Part {
            partId: "WHEEL_UP"
            label: "▲"
            color: "transparent"
            border.width: 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: mouse.u * 0.12
            width: mouse.u * 0.5
            height: mouse.u * 0.32
        }

        // Solid behind the wheel so the gap between the buttons does not show.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: mouse.u * 0.48
            width: mouse.u * 0.34
            height: mouse.u * 0.72
            radius: width / 2
            color: keyboard.base
        }

        Part {
            partId: "BTN_MIDDLE"
            anchors.horizontalCenter: parent.horizontalCenter
            y: mouse.u * 0.48
            width: mouse.u * 0.34
            height: mouse.u * 0.72
            radius: width / 2
        }

        // Sideways scrolling only appears when something is bound to it.
        Part {
            partId: "WHEEL_LEFT"
            label: "◀"
            visible: keyboard.bound["WHEEL_LEFT"] === true || keyboard.lit.indexOf(partId) !== -1
            color: "transparent"
            border.width: 0
            x: parent.width / 2 - mouse.u * 0.58
            y: mouse.u * 0.68
            width: mouse.u * 0.32
            height: mouse.u * 0.32
        }

        Part {
            partId: "WHEEL_RIGHT"
            label: "▶"
            visible: keyboard.bound["WHEEL_RIGHT"] === true || keyboard.lit.indexOf(partId) !== -1
            color: "transparent"
            border.width: 0
            x: parent.width / 2 + mouse.u * 0.26
            y: mouse.u * 0.68
            width: mouse.u * 0.32
            height: mouse.u * 0.32
        }

        // Thumb buttons on the left side.
        Part {
            partId: "BTN_EXTRA"
            x: mouse.gap * 1.5
            y: mouse.u * 2.2
            width: mouse.u * 0.2
            height: mouse.u * 0.55
            radius: width / 2
        }

        Part {
            partId: "BTN_SIDE"
            x: mouse.gap * 1.5
            y: mouse.u * 2.85
            width: mouse.u * 0.2
            height: mouse.u * 0.55
            radius: width / 2
        }

        Part {
            partId: "WHEEL_DOWN"
            label: "▼"
            color: "transparent"
            border.width: 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: mouse.u * 1.24
            width: mouse.u * 0.5
            height: mouse.u * 0.32
        }
    }

    Repeater {
        model: keyboard.keys

        delegate: Item {
            id: cap
            required property var modelData
            readonly property string mod: keyboard.modOf(modelData.name)
            readonly property string keyId: mod || modelData.name
            readonly property var label: keyboard.labels(modelData.name)
            readonly property bool inLayer: mod !== "" && keyboard.activeMods.indexOf(mod) !== -1
            readonly property bool isLit: keyboard.lit.indexOf(keyId) !== -1
            readonly property bool isBound: keyboard.bound[keyId] === true
            readonly property bool hovered: keyboard.hoverKey === keyId
            readonly property real gap: keyboard.unit * 0.09
            readonly property real radius: Math.max(3, keyboard.unit * 0.1)
            readonly property color fill: inLayer ? Util.alpha(keyboard.accent, 0.32)
                                        : isLit ? Util.alpha(keyboard.accent, 0.32)
                                        : Util.alpha(keyboard.fg, isBound ? 0.035 : 0.015)
            readonly property color edge: inLayer || isLit ? keyboard.accent
                                        : Util.alpha(keyboard.fg, hovered ? 0.8 : isBound ? 0.5 : 0.13)
            readonly property real edgeWidth: inLayer || isLit ? 1.5 : 1
            readonly property color ink: inLayer || isLit ? keyboard.accent
                                       : Util.alpha(keyboard.fg, isBound || mod ? 0.92 : 0.32)

            x: modelData.x * keyboard.unit + gap / 2
            y: modelData.y * keyboard.unit + gap / 2
            width: modelData.w * keyboard.unit - gap
            height: (modelData.h || 1) * keyboard.unit - gap

            Rectangle {
                visible: cap.modelData.shape !== "iso-enter"
                anchors.fill: parent
                radius: cap.radius
                color: cap.fill
                border.width: cap.edgeWidth
                border.color: cap.edge
                }

            // ISO Enter: wide on the upper row, a quarter key narrower below.
            // Built for that key only.
            Loader {
                anchors.fill: parent
                active: cap.modelData.shape === "iso-enter"
                sourceComponent: Shape {
                    id: isoEnter
                    // The default (geometry) renderer: the curve renderer drew this
                    // shape's outline but not its fill.
                    preferredRendererType: Shape.GeometryRenderer
                    antialiasing: true
                    readonly property real r: cap.radius
                    readonly property real step: keyboard.unit * 0.25
                    readonly property real mid: keyboard.unit - cap.gap
    
                    ShapePath {
                        fillColor: cap.fill
                        fillRule: ShapePath.WindingFill
                        strokeColor: cap.edge
                        strokeWidth: cap.edgeWidth
                        startX: isoEnter.r; startY: 0
                        PathLine { x: cap.width - isoEnter.r; y: 0 }
                        PathArc { x: cap.width; y: isoEnter.r; radiusX: isoEnter.r; radiusY: isoEnter.r }
                        PathLine { x: cap.width; y: cap.height - isoEnter.r }
                        PathArc { x: cap.width - isoEnter.r; y: cap.height; radiusX: isoEnter.r; radiusY: isoEnter.r }
                        PathLine { x: isoEnter.step + isoEnter.r; y: cap.height }
                        PathArc { x: isoEnter.step; y: cap.height - isoEnter.r; radiusX: isoEnter.r; radiusY: isoEnter.r }
                        PathLine { x: isoEnter.step; y: isoEnter.mid }
                        PathLine { x: isoEnter.r; y: isoEnter.mid }
                        PathArc { x: 0; y: isoEnter.mid - isoEnter.r; radiusX: isoEnter.r; radiusY: isoEnter.r }
                        PathLine { x: 0; y: isoEnter.r }
                        PathArc { x: isoEnter.r; y: 0; radiusX: isoEnter.r; radiusY: isoEnter.r }
                    }
                }
            }

            // One baseline for every keycap label, whatever its size.
            Text {
                x: keyboard.unit * 0.14
                anchors.baseline: parent.top
                anchors.baselineOffset: keyboard.unit * 0.36
                textFormat: Text.PlainText
                text: cap.label[0]
                font.family: keyboard.fontFamily
                font.pixelSize: Math.round(keyboard.unit * (cap.label[0].length > 1 ? 0.24 : 0.3))
                color: cap.ink
            }

            // The shifted character, as printed on a real keycap.
            Text {
                visible: text !== ""
                anchors.right: parent.right
                anchors.rightMargin: keyboard.unit * 0.12
                anchors.bottom: parent.bottom
                anchors.bottomMargin: keyboard.unit * 0.06
                textFormat: Text.PlainText
                text: cap.label[1]
                font.family: keyboard.fontFamily
                font.pixelSize: Math.round(keyboard.unit * 0.22)
                color: Util.alpha(cap.ink, 0.6)
            }

            MouseArea {
                id: capArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: cap.mod || cap.isBound ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: keyboard.keyClicked(cap.keyId)
            }

            readonly property bool pointed: keyboard.pointerArmed && capArea.containsMouse
            onPointedChanged: {
                if (pointed) keyboard.keyHovered(keyId)
                else if (keyboard.hoverKey === keyId) keyboard.keyHovered("")
            }
        }
    }
}
