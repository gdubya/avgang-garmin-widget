using Toybox.Application as App;
using Toybox.WatchUi as Ui;

// Minimal host app for the tests, named as manifest.xml's entry class
class RuterWidgetApp extends App.AppBase {
    function initialize() {
        AppBase.initialize();
    }
    function getInitialView() {
        return [new Ui.View()];
    }
}
