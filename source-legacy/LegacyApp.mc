using Toybox.Application as App;

// Entry point on Connect IQ 1.x watches (see monkey.jungle). Named like the
// modern entry point because the manifest names one entry class.
class RuterWidgetApp extends App.AppBase {

    hidden var _client;

    function initialize() {
        AppBase.initialize();
        _client = new LegacyClient(new DepartureModel.StopBoardState());
    }

    function getInitialView() {
        return [new LegacyView(_client, false), new LegacyDelegate(_client, false)];
    }

    // Settings were edited in Garmin Connect Mobile
    function onSettingsChanged() {
        _client.reload();
    }
}
