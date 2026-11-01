import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;
import DepartureModel;

(:glance)
class RuterGlanceView extends WatchUi.GlanceView {

    private var _client as EnturApiClient;

    public function initialize(client as EnturApiClient) {
        GlanceView.initialize();
        self._client = client;
    }

    public function onShow() as Void {
        var state = self._client.getState();
        if (state.status == :idle) {
            self._client.refreshDepartures();
        } else {
            state.recalculateCountdowns(Time.now().value());
        }
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var state = self._client.getState();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var accentColor = 0xFF0000;
        if (state.departures.size() > 0) {
            accentColor = state.departures[0].modeColor;
        }

        // Left mode accent bar
        dc.setColor(accentColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, 6, 4, height - 12);

        // Top line: Stop name
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var title = state.stopName;
        if (title.length() > 18) {
            title = title.substring(0, 17) + ".";
        }
        dc.drawText(10, 4, Graphics.FONT_XTINY, title, Graphics.TEXT_JUSTIFY_LEFT);

        // Bottom line: Next departure or status
        var summaryText = "Press to load";
        var summaryColor = Graphics.COLOR_WHITE;

        if (state.departures.size() > 0) {
            var next = state.departures[0];
            var dest = next.destination;
            if (dest.length() > 10) {
                dest = dest.substring(0, 9) + ".";
            }
            summaryText = next.modeLabel + " " + next.lineCode + " " + dest + " " + next.formatCountdown();
        } else if (state.status == :loading) {
            summaryText = "Fetching...";
            summaryColor = Graphics.COLOR_LT_GRAY;
        } else if (state.status == :error) {
            summaryText = state.errorMessage;
            summaryColor = Graphics.COLOR_ORANGE;
        } else if (state.status == :ready) {
            summaryText = "No departures";
            summaryColor = Graphics.COLOR_LT_GRAY;
        }

        dc.setColor(summaryColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(10, height / 2, Graphics.FONT_TINY, summaryText, Graphics.TEXT_JUSTIFY_LEFT);
    }
}
