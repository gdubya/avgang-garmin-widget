import Toybox.Application.Properties;
import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.WatchUi;
import DepartureModel;

class RuterWidgetDelegate extends WatchUi.BehaviorDelegate {

    private var _client as EnturApiClient;

    public function initialize(client as EnturApiClient) {
        BehaviorDelegate.initialize();
        self._client = client;
    }

    // START/STOP button: immediate refresh
    public function onSelect() as Boolean {
        self._client.refreshDepartures();
        return true;
    }

    // DOWN button: scroll down through departures
    public function onNextPage() as Boolean {
        var state = self._client.getState();
        var maxOffset = state.departures.size() - RuterWidgetView.VISIBLE_ROWS;
        if (maxOffset > 0 && state.scrollOffset < maxOffset) {
            state.scrollOffset = state.scrollOffset + 1;
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

    // UP button: scroll up through departures
    public function onPreviousPage() as Boolean {
        var state = self._client.getState();
        if (state.scrollOffset > 0) {
            state.scrollOffset = state.scrollOffset - 1;
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

    // Hold UP / MENU button: open on-watch configuration menu
    public function onMenu() as Boolean {
        var menu = new WatchUi.Menu2({ :title => "Avgang Config" });

        menu.addItem(new WatchUi.MenuItem(
            "Stop Source",
            self.formatSourceSubLabel(self._client.getActiveStopMode()),
            :stopSource,
            null
        ));

        var currentStopDesc = self._client.getState().stopName;
        var pinnedName = Storage.getValue("pinnedStopName");
        if (pinnedName instanceof String && pinnedName.length() > 0) {
            currentStopDesc = "Pinned: " + pinnedName;
        }
        menu.addItem(new WatchUi.MenuItem(
            "Pin Current Stop",
            currentStopDesc,
            :pinCurrent,
            null
        ));

        var sortSub = self._client.getSortByModeFirst() ? "Mode + Time" : "Time Only";
        menu.addItem(new WatchUi.MenuItem(
            "Sort Order",
            sortSub,
            :sortOrder,
            null
        ));

        WatchUi.pushView(
            menu,
            new RuterSettingsMenuDelegate(self._client),
            WatchUi.SLIDE_UP
        );
        return true;
    }

    public static function formatSourceSubLabel(mode as Number) as String {
        if (mode == DepartureModel.MODE_GPS) {
            return "GPS Nearest Stop";
        } else if (mode == DepartureModel.MODE_FAV_1) {
            var q1 = Properties.getValue("stopQuery1");
            return "Fav 1: " + ((q1 instanceof String) ? q1 : "");
        } else if (mode == DepartureModel.MODE_FAV_2) {
            var q2 = Properties.getValue("stopQuery2");
            return "Fav 2: " + ((q2 instanceof String) ? q2 : "");
        } else if (mode == DepartureModel.MODE_FAV_3) {
            var q3 = Properties.getValue("stopQuery3");
            return "Fav 3: " + ((q3 instanceof String) ? q3 : "");
        } else if (mode == DepartureModel.MODE_PINNED) {
            var pName = Storage.getValue("pinnedStopName");
            return "Pinned: " + ((pName instanceof String) ? pName : "None");
        }
        return "Favorite 1";
    }
}

class RuterSettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _client as EnturApiClient;
    private var _sourceChanged as Boolean = false;

    public function initialize(client as EnturApiClient) {
        Menu2InputDelegate.initialize();
        self._client = client;
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :stopSource) {
            var nextMode = (self._client.getActiveStopMode() + 1) % 5;
            self._client.setActiveStopMode(nextMode);
            item.setSubLabel(RuterWidgetDelegate.formatSourceSubLabel(nextMode));
            self._sourceChanged = true;
        } else if (id == :pinCurrent) {
            if (self._client.pinCurrentStop()) {
                item.setSubLabel("Saved: " + self._client.getState().stopName);
                self._sourceChanged = true;
            } else {
                item.setSubLabel("Wait for stop load");
            }
        } else if (id == :sortOrder) {
            var nextSort = !self._client.getSortByModeFirst();
            self._client.setSortByModeFirst(nextSort);
            item.setSubLabel(nextSort ? "Mode + Time" : "Time Only");
        }
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (self._sourceChanged) {
            self._client.refreshDepartures();
        }
    }
}
