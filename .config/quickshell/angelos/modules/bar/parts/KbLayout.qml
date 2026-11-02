import QtQuick
import qs.config
import qs.services
import qs.widgets

PxButton {
    // screen readers (widgets/A11y.js): what this icon is
    Accessible.name: I18n.t("Раскладка клавиатуры", "Keyboard layout")
    Accessible.description: (Fcitx.usable ? Fcitx.name : Niri.layoutShort) + (CapsLock.on ? ", Caps Lock" : "")

    // the layouts can live in niri or in fcitx5 (issue #136): the one that has something to
    // switch between wins; with neither, only Caps Lock can bring the button up
    readonly property bool viaFcitx: Fcitx.usable
    // Caps Lock on: the key's arrow next to the layout, the button lit (with one layout it shows up for that alone)
    visible: viaFcitx || Niri.keyboardLayouts.length > 1 || CapsLock.on
    compact: true
    flat: true
    icon: CapsLock.on ? "caps" : ""
    checked: CapsLock.on
    text: viaFcitx ? Fcitx.shortLabel : Niri.layoutShort
    onClicked: {
        if (viaFcitx)
            Fcitx.next();
        else
            Niri.switchLayout(true);
    }
}
