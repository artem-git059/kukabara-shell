import QtQuick

// Entries made from a model (a Repeater of rows): `delegate` is a Cat entry.
Item {
    id: root

    readonly property bool isCatRepeat: true
    property alias model: inst.model
    property alias delegate: inst.delegate
    property var entries: []
    visible: false
    Instantiator {
        id: inst
        onObjectAdded: (i, o) => {
            o.parent = root;
            scheduleSync();
        }
        onObjectRemoved: (i, o) => scheduleSync()
    }
    // `entries` feeds a Repeater in the catalog page: changing it from inside the Instantiator's
    // own add/remove (that is, while it is clearing or populating) rebuilds that Repeater under
    // it and aborts Quickshell (QQmlInstantiatorPrivate::clear → Repeater::setModel, seen on the
    // Mac page). Gather the instances after the Instantiator has settled, once.
    property bool syncQueued: false
    function scheduleSync() {
        if (syncQueued)
            return;
        syncQueued = true;
        Qt.callLater(syncEntries);
    }
    function syncEntries() {
        syncQueued = false;
        const e = [];
        for (let i = 0; i < inst.count; i++) {
            const o = inst.objectAt(i);
            if (o)
                e.push(o);
        }
        entries = e;
    }
}
