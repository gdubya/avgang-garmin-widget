import Toybox.Application.Properties;
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
        var nowEpoch = Time.now().value();
        if (state.status == :idle || (nowEpoch - state.lastUpdatedEpoch) > 30 || state.departures.size() == 0) {
            if (state.status != :loading) {
                self._client.refreshGlanceDepartures();
            }
        } else {
            state.recalculateCountdowns(nowEpoch);
        }
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var state = self._client.getState();

        // Recalculate countdowns to keep minutesUntil accurate
        state.recalculateCountdowns(Time.now().value());

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var accentColor = 0xFF0000;
        if (state.departures.size() > 0) {
            accentColor = state.departures[0].modeColor;
        }

        // Left mode accent bar
        dc.setColor(accentColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, 6, 4, height - 12);

        // One row (the next departure), or one per direction when the setting is on
        var rows = state.departures.slice(0, 1);
        var rowHeight = dc.getFontHeight(Graphics.FONT_TINY);
        var rowY = height / 2;
        var showTitle = true;
        if (Properties.getValue("glanceShowDirections") == true) {
            rows = DepartureModel.nextPerDirection(state.departures);
            if (rows.size() > 1) {
                rowY = height - 2 * rowHeight;
                // Short glance: drop the stop name and centre the two rows
                if (rowY < 4 + dc.getFontHeight(Graphics.FONT_XTINY)) {
                    showTitle = false;
                    rowY = rowY / 2;
                }
            }
        }

        // Top line: Stop name
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var title = showTitle ? state.stopName : "";
        var maxTitleWidth = width - 14;
        if (dc.getTextWidthInPixels(title, Graphics.FONT_XTINY) > maxTitleWidth) {
            while (title.length() > 0 && dc.getTextWidthInPixels(title + ".", Graphics.FONT_XTINY) > maxTitleWidth) {
                title = title.substring(0, title.length() - 1);
            }
            title = title + ".";
        }
        dc.drawText(10, 4, Graphics.FONT_XTINY, title, Graphics.TEXT_JUSTIFY_LEFT);

        // Bottom line: Next departure or status
        for (var i = 0; i < rows.size(); i++) {
            var next = rows[i];
            var y = rowY + i * rowHeight;
            var countdownText = next.formatCountdown();
            var countdownColor = (next.minutesUntil <= 2) ? 0x00FF00 : Graphics.COLOR_WHITE;

            // Draw countdown right-aligned on the right edge
            var rightX = width - 4;
            dc.setColor(countdownColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(rightX, y, Graphics.FONT_TINY, countdownText, Graphics.TEXT_JUSTIFY_RIGHT);

            // Calculate remaining width for departure line/destination on the left
            var countdownWidth = dc.getTextWidthInPixels(countdownText, Graphics.FONT_TINY);
            var maxLeftWidth = (rightX - countdownWidth - 5) - 10;
            if (maxLeftWidth < 20) {
                maxLeftWidth = 20;
            }

            var leftText = self.fitDepartureText(dc, next, maxLeftWidth, rows.size() == 1);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(10, y, Graphics.FONT_TINY, leftText, Graphics.TEXT_JUSTIFY_LEFT);
        }
        if (rows.size() == 0) {
            var summaryText = "Press to load";
            var summaryColor = Graphics.COLOR_WHITE;

            if (state.status == :loading) {
                summaryText = "Fetching...";
                summaryColor = Graphics.COLOR_LT_GRAY;
            } else if (state.status == :error) {
                summaryText = state.errorMessage;
                summaryColor = Graphics.COLOR_ORANGE;
            } else if (state.status == :ready) {
                summaryText = "No departures";
                if (state.routeFilter.size() > 0) {
                    summaryText = "None on your lines";
                } else if (state.modeFilter.size() > 0) {
                    summaryText = "No " + DepartureModel.joinCodes(state.modeFilter) + " departures";
                }
                summaryColor = Graphics.COLOR_LT_GRAY;
            }

            var maxMsgWidth = width - 14;
            if (dc.getTextWidthInPixels(summaryText, Graphics.FONT_TINY) > maxMsgWidth) {
                while (summaryText.length() > 0 && dc.getTextWidthInPixels(summaryText + ".", Graphics.FONT_TINY) > maxMsgWidth) {
                    summaryText = summaryText.substring(0, summaryText.length() - 1);
                }
                summaryText = summaryText + ".";
            }

            dc.setColor(summaryColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(10, height / 2, Graphics.FONT_TINY, summaryText, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    private function fitDepartureText(
        dc as Graphics.Dc,
        next as DepartureModel.DepartureItem,
        maxWidth as Number,
        withMode as Boolean
    ) as String {
        // 1. Try full: "BUS 375 Helsfyr" (single row only, so two rows look alike)
        var fullText = next.modeLabel + " " + next.lineCode + " " + next.destination;
        if (withMode && dc.getTextWidthInPixels(fullText, Graphics.FONT_TINY) <= maxWidth) {
            return fullText;
        }

        // 2. Try line + destination: "375 Helsfyr"
        var lineDestText = next.lineCode + " " + next.destination;
        if (dc.getTextWidthInPixels(lineDestText, Graphics.FONT_TINY) <= maxWidth) {
            return lineDestText;
        }

        // 3. Truncate destination with line code prefix: "375 Helsf."
        var prefix = next.lineCode + " ";
        var dest = next.destination;
        while (dest.length() > 0 && dc.getTextWidthInPixels(prefix + dest + ".", Graphics.FONT_TINY) > maxWidth) {
            dest = dest.substring(0, dest.length() - 1);
        }

        if (dest.length() > 0) {
            return prefix + dest + ".";
        }

        return next.lineCode;
    }
}
