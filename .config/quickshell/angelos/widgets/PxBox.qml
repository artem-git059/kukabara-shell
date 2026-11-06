import QtQuick
import QtQuick.Effects
import qs.config

// Win98-style bevelled box. raised by default, `sunken` for inputs/pressed.
// By day (Theme.zine) it is flat: the outline alone, no bevels.
// `hell: Theme.hell` gives it hell's obsidian bevels (Theme.realm).
// Under the Aero skin it is a pane of glass: rounded, lit from above, rimmed with light,
// with the fill a soft gradient instead of a bevel (Theme.aeroBase).
Item {
    id: root

    property bool hell: false
    readonly property string settingsSkin: hell ? "classic" : Theme.settingsSkinFor(root.parent)
    // the P5 settings window: a flat paper plate with a black outline
    readonly property bool p5: settingsSkin === "p5"
    // Aero's glass (Theme.aeroLook): every surface of the skin, menus and the bar too
    readonly property bool aero: !hell && Theme.aeroLook
    property color color: hell ? Theme.hellFace : p5 ? Theme.p5Paper2 : Theme.face
    property int bevel: settingsSkin === "windose" ? Math.max(1, Math.floor(Theme.u / 2)) : Theme.u
    property bool sunken: false
    property bool outline: true
    property bool forceFlat: false
    // a pill: the face rounded to its shorter side (the standard theme's status-bar/bubbles look)
    property bool pill: false
    property bool flat: forceFlat || settingsSkin === "windose" || p5 || aero || (Theme.zine && !hell)
    property bool shadow: false
    property int shadowSize: Theme.u * 2
    property color shadowColor: Qt.alpha(Theme.shadow, Theme.shadowAlpha)
    property color hiColor: hell ? Theme.hellHi : settingsSkin === "windose" ? Theme.windoseLine : Theme.hi
    property color loColor: hell ? Theme.hellLo : settingsSkin === "windose" ? Theme.windoseLine : Theme.lo
    property color edgeColor: hell ? Theme.hellEdge : settingsSkin === "windose" ? Theme.windoseLine : p5 ? Theme.p5Black : Theme.edge
    readonly property int ob: outline ? bevel : 0
    readonly property int inset: ob + (flat ? 0 : bevel)
    // the glass corner; a bar or a full-width strip sets 0 to keep the screen's edge clean
    property int radius: pill ? Math.round(Math.min(width, height) / 2) : aero ? Theme.aeroRadius : 0
    default property alias content: inner.data

    // hard pixel shadow (right + bottom strips so translucent boxes stay clean)
    Rectangle {
        visible: root.shadow && !root.aero
        x: root.width
        y: root.shadowSize
        width: root.shadowSize
        height: root.height
        color: root.shadowColor
    }
    Rectangle {
        visible: root.shadow && !root.aero
        x: root.shadowSize
        y: root.height
        width: root.width
        height: root.shadowSize
        color: root.shadowColor
    }
    // Aero: a soft shadow instead of the stepped one
    RectangularShadow {
        visible: root.aero && root.shadow
        anchors.fill: parent
        radius: root.radius
        blur: Theme.aeroRadius * 4
        spread: -Math.max(1, Theme.aeroRadius / 2)
        offset.y: Math.max(2, Theme.aeroRadius)
        color: Qt.alpha(Theme.shadow, Theme.dark ? 0.6 : 0.35)
        cached: true
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.aero ? "transparent" : root.color
        gradient: root.aero ? aeroFill : null
        border.width: root.aero ? 1 : root.ob
        border.color: root.aero ? Theme.aeroRimSoft : root.edgeColor
    }
    Gradient {
        id: aeroFill
        orientation: Gradient.Vertical
        GradientStop {
            position: 0
            color: Qt.lighter(root.color, Theme.dark ? 1.3 : 1.12)
        }
        GradientStop {
            position: 0.42
            color: root.color
        }
        GradientStop {
            position: 1
            color: Qt.darker(root.color, Theme.dark ? 1.22 : 1.03)
        }
    }
    // Aero's gloss: the light caught on the top half of the pane
    Rectangle {
        visible: root.aero
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, root.radius - 1)
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop {
                position: 0
                color: Theme.aeroGloss
            }
            GradientStop {
                position: 0.52
                color: Qt.rgba(1, 1, 1, 0.03)
            }
            GradientStop {
                position: 1
                color: "transparent"
            }
        }
    }
    // the bright rim inside the edge, brightest at the top
    Rectangle {
        visible: root.aero
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, root.radius - 1)
        color: "transparent"
        border.width: 1
        border.color: Theme.aeroRim
        opacity: Theme.dark ? 0.55 : 0.8
    }
    Rectangle {
        visible: !root.flat
        x: root.ob
        y: root.ob
        width: root.width - 2 * root.ob
        height: root.bevel
        color: root.sunken ? root.loColor : root.hiColor
    }
    Rectangle {
        visible: !root.flat
        x: root.ob
        y: root.ob
        width: root.bevel
        height: root.height - 2 * root.ob
        color: root.sunken ? root.loColor : root.hiColor
    }
    Rectangle {
        visible: !root.flat
        x: root.ob + root.bevel
        y: root.height - root.ob - root.bevel
        width: root.width - 2 * root.ob - root.bevel
        height: root.bevel
        color: root.sunken ? root.hiColor : root.loColor
    }
    Rectangle {
        visible: !root.flat
        x: root.width - root.ob - root.bevel
        y: root.ob + root.bevel
        width: root.bevel
        height: root.height - 2 * root.ob - root.bevel
        color: root.sunken ? root.hiColor : root.loColor
    }

    Item {
        id: inner
        anchors.fill: parent
        anchors.margins: root.inset
    }
}
