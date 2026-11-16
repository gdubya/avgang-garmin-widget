using Toybox.WatchUi as Ui;

// One delegate for both levels. On Connect IQ 1.x UP/DOWN on a widget's first
// page belong to the watch's widget loop, so START opens the list (detail).
// There UP/DOWN scroll, and START or hold-UP opens the menu.
class LegacyDelegate extends Ui.BehaviorDelegate {

    hidden var _client;
    hidden var _detail;

    function initialize(client, detail) {
        BehaviorDelegate.initialize();
        _client = client;
        _detail = detail;
    }

    function onSelect() {
        if (_detail) {
            return onMenu();
        }
        _client.getState().scrollOffset = 0;
        Ui.pushView(new LegacyView(_client, true), new LegacyDelegate(_client, true), Ui.SLIDE_LEFT);
        return true;
    }

    function onNextPage() {
        return scroll(1);
    }

    function onPreviousPage() {
        return scroll(-1);
    }

    // The view clamps the offset to the last full page
    hidden function scroll(step) {
        var state = _client.getState();
        if (_detail && state.scrollOffset + step >= 0) {
            state.scrollOffset = state.scrollOffset + step;
            Ui.requestUpdate();
        }
        return _detail;
    }

    // Classic WatchUi.Menu (Menu2 is API 3.0), flat: one press per action
    function onMenu() {
        var mode = _client.getActiveStopMode();
        var menu = new Ui.Menu();
        menu.setTitle("Avgang");
        menu.addItem("Refresh", :refresh);
        // Favourites show their own filters, e.g. "* Helsfyr (bus)"
        menu.addItem(mark(mode == 1) + _client.getFavName(1) + _client.favTag(1), :fav1);
        menu.addItem(mark(mode == 2) + _client.getFavName(2) + _client.favTag(2), :fav2);
        menu.addItem(mark(mode == 3) + _client.getFavName(3) + _client.favTag(3), :fav3);
        menu.addItem(mark(mode == 0) + "GPS nearest", :gps);
        menu.addItem(mark(mode == 4) + "Pin: " + _client.text("pinnedStopName"), :pinned);
        var lines = DepartureModel.joinCodes(_client.codes("routeFilter"));
        if (lines.length() > 0) {
            menu.addItem("Lines " + lines + (_client.isOn("routeFilterEnabled") ? ": ON" : ": off"), :filter);
        }
        menu.addItem("Pin this stop", :pin);
        menu.addItem(_client.isOn("sortByModeFirst") ? "Sort: mode" : "Sort: time", :sort);
        Ui.pushView(menu, new LegacyMenuDelegate(_client), Ui.SLIDE_UP);
        return true;
    }

    hidden function mark(active) {
        return active ? "* " : "";
    }
}

class LegacyMenuDelegate extends Ui.MenuInputDelegate {

    hidden var _client;

    function initialize(client) {
        MenuInputDelegate.initialize();
        _client = client;
    }

    function onMenuItem(item) {
        var mode = { :gps => 0, :fav1 => 1, :fav2 => 2, :fav3 => 3, :pinned => 4 }[item];
        if (mode != null) {
            _client.setActiveStopMode(mode);
        } else if (item == :filter) {
            _client.toggle("routeFilterEnabled");
        } else if (item == :sort) {
            _client.toggle("sortByModeFirst");
        } else if (item == :pin) {
            _client.pinCurrentStop();
        } else {
            _client.refreshDepartures();
        }
    }
}
