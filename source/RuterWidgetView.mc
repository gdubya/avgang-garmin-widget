import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;
import DepartureModel;

class RuterWidgetView extends WatchUi.View {

    public static const VISIBLE_ROWS = 3;

    private var _client as EnturApiClient;
    private var _timer as Timer.Timer or Null = null;
    private var _tickCount as Number = 0;

    public function initialize(client as EnturApiClient) {
        View.initialize();
        self._client = client;
    }

    public function onShow() as Void {
        var state = self._client.getState();
        var nowEpoch = Time.now().value();
        if (state.status == :idle || (nowEpoch - state.lastUpdatedEpoch) > 60) {
            self._client.refreshDepartures();
        } else {
            state.recalculateCountdowns(nowEpoch);
        }

        if (self._timer == null) {
            self._timer = new Timer.Timer();
            self._timer.start(method(:onTimerTick), 15000, true);
        }
    }

    public function onHide() as Void {
        if (self._timer != null) {
            self._timer.stop();
            self._timer = null;
        }
    }

    public function onTimerTick() as Void {
        self._tickCount = self._tickCount + 1;
        var nowEpoch = Time.now().value();
        self._client.getState().recalculateCountdowns(nowEpoch);

        if (self._tickCount >= 4) {
            self._tickCount = 0;
            self._client.refreshDepartures();
        } else {
            WatchUi.requestUpdate();
        }
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;
        var state = self._client.getState();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // 1. Header: Active stop mode badge + distance
        var modeBadge = self.getStopSourceLabel();
        if (state.distanceMeters != null) {
            modeBadge = modeBadge + " • " + state.distanceMeters.toString() + "m";
        }
        if (state.status == :loading) {
            modeBadge = modeBadge + " • SYNC";
        }
        dc.setColor(0x00AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, 10, Graphics.FONT_XTINY, modeBadge, Graphics.TEXT_JUSTIFY_CENTER);

        // 2. Stop Name (truncated to fit 240x240 top chord)
        var stopTitle = state.stopName;
        if (stopTitle.length() > 16) {
            stopTitle = stopTitle.substring(0, 15) + ".";
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, 29, Graphics.FONT_TINY, stopTitle, Graphics.TEXT_JUSTIFY_CENTER);

        // Header divider
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(28, 55, width - 28, 55);

        // 3. Body: Departures list or status message
        var total = state.departures.size();
        if (total == 0) {
            var msg = "No departures";
            var msgColor = Graphics.COLOR_LT_GRAY;
            if (state.status == :loading) {
                msg = "Fetching Entur...";
            } else if (state.status == :error) {
                msg = state.errorMessage;
                msgColor = Graphics.COLOR_ORANGE;
            }
            dc.setColor(msgColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, (height / 2) - 10, Graphics.FONT_SMALL, msg, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            var rowStartY = 60;
            var rowHeight = 43;
            for (var r = 0; r < VISIBLE_ROWS; r++) {
                var idx = state.scrollOffset + r;
                if (idx >= total) {
                    break;
                }
                self.drawDepartureRow(dc, state.departures[idx], rowStartY + (r * rowHeight), width);
            }

            // Draw right-edge scroll indicator if more than VISIBLE_ROWS
            if (total > VISIBLE_ROWS) {
                self.drawScrollIndicator(dc, state.scrollOffset, total, width);
            }
        }

        // 4. Footer: Sort order & Menu hint
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(42, 194, width - 42, 194);

        var sortTag = self._client.getSortByModeFirst() ? "Mode+Time" : "Time Only";
        var footer = sortTag + " • Hold UP: Menu";
        if (total > VISIBLE_ROWS) {
            var endIdx = state.scrollOffset + VISIBLE_ROWS;
            if (endIdx > total) {
                endIdx = total;
            }
            footer = sortTag + " (" + (state.scrollOffset + 1).toString() + "-" + endIdx.toString() + "/" + total.toString() + ")";
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, 200, Graphics.FONT_XTINY, footer, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawDepartureRow(
        dc as Graphics.Dc,
        item as DepartureModel.DepartureItem,
        rowY as Number,
        width as Number
    ) as Void {
        // Mode + Line badge pill on the left
        var pillX = 16;
        var pillY = rowY + 6;
        var pillW = 58;
        var pillH = 28;

        dc.setColor(item.modeColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(pillX, pillY, pillW, pillH, 5);

        var badgeText = item.modeLabel + " " + item.lineCode;
        if (badgeText.length() > 7) {
            badgeText = item.lineCode;
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            pillX + (pillW / 2),
            pillY + 3,
            Graphics.FONT_XTINY,
            badgeText,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // Destination text
        var dest = item.destination;
        if (dest.length() > 10) {
            dest = dest.substring(0, 9) + ".";
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(80, rowY + 8, Graphics.FONT_TINY, dest, Graphics.TEXT_JUSTIFY_LEFT);

        // Real-time indicator dot (Green = live SIRI, Yellow = scheduled)
        var rtColor = item.isRealtime ? 0x00FF00 : 0xFFAA00;
        dc.setColor(rtColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(width - 54, rowY + 20, 3);

        // Countdown text on the right
        var timeColor = (item.minutesUntil <= 2) ? 0x00FF00 : Graphics.COLOR_WHITE;
        dc.setColor(timeColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            width - 16,
            rowY + 8,
            Graphics.FONT_TINY,
            item.formatCountdown(),
            Graphics.TEXT_JUSTIFY_RIGHT
        );
    }

    private function drawScrollIndicator(
        dc as Graphics.Dc,
        offset as Number,
        total as Number,
        width as Number
    ) as Void {
        var trackX = width - 8;
        var trackY = 72;
        var trackH = 104;

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(trackX, trackY, trackX, trackY + trackH);

        var maxOffset = total - VISIBLE_ROWS;
        if (maxOffset < 1) {
            maxOffset = 1;
        }
        var thumbH = 26;
        var thumbY = trackY + ((offset * (trackH - thumbH)) / maxOffset);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(trackX - 1, thumbY, 3, thumbH);
    }

    private function getStopSourceLabel() as String {
        var mode = self._client.getActiveStopMode();
        if (mode == DepartureModel.MODE_GPS) {
            return "GPS NEAREST";
        } else if (mode == DepartureModel.MODE_FAV_1) {
            return "FAV STOP 1";
        } else if (mode == DepartureModel.MODE_FAV_2) {
            return "FAV STOP 2";
        } else if (mode == DepartureModel.MODE_FAV_3) {
            return "FAV STOP 3";
        } else if (mode == DepartureModel.MODE_PINNED) {
            return "PINNED STOP";
        }
        return "RUTER";
    }
}
