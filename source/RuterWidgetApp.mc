import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;
import DepartureModel;

(:glance)
class RuterWidgetApp extends Application.AppBase {

    private var _state as DepartureModel.StopBoardState;
    private var _client as EnturApiClient;

    public function initialize() {
        AppBase.initialize();
        self._state = new DepartureModel.StopBoardState();
        self._client = new EnturApiClient(self._state);
    }

    public function onStart(state as Dictionary?) as Void {
    }

    public function onStop(state as Dictionary?) as Void {
    }

    public function getInitialView() as [Views] or [Views, InputDelegates] {
        return [
            new RuterWidgetView(self._client),
            new RuterWidgetDelegate(self._client)
        ];
    }

    public function getGlanceView() as [GlanceView] or [GlanceView, GlanceViewDelegate] or Null {
        return [new RuterGlanceView(self._client)];
    }

    // Triggered automatically when user updates settings in Garmin Connect Mobile
    public function onSettingsChanged() as Void {
        self._client.refreshDepartures();
    }
}
