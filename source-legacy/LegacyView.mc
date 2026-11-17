using Toybox.Graphics as Gfx;
using Toybox.Math as Math;
using Toybox.Time as Time;
using Toybox.Timer as Timer;
using Toybox.WatchUi as Ui;

// Departure board for the semi-round 215x180 screen of the Forerunner 230/235.
// Used twice: the widget page (3 rows) and the list pushed with START
// (detail: 4 rows, scrolls).
class LegacyView extends Ui.View {

    hidden var _client;
    hidden var _detail;
    hidden var _timer;
    hidden var _ticks = 0;

    function initialize(client, detail) {
        View.initialize();
        _client = client;
        _detail = detail;
    }

    function onShow() {
        if ((Time.now().value() - _client.getState().lastUpdatedEpoch) > 60) {
            _client.autoRefresh();
        }
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 15000, true);
    }

    function onHide() {
        _timer.stop();
    }

    // Countdowns tick every 15 s, the board is fetched again every 60 s
    function onTick() as Void {
        _ticks = (_ticks + 1) % 4;
        _client.recalc();
        if (_ticks == 0 || _client.gpsWait) {
            _client.autoRefresh();
        }
        Ui.requestUpdate();
    }

    // Usable half-width for text spanning yTop..yBottom. The screen is a circle
    // of diameter = width with the top and bottom cut flat.
    hidden function halfWidth(dc, yTop, yBottom) {
        var r = dc.getWidth() / 2.0;
        var d1 = (yTop - (dc.getHeight() / 2.0)).abs();
        var d2 = (yBottom - (dc.getHeight() / 2.0)).abs();
        var dy = (d1 > d2) ? d1 : d2;
        return (dy >= r) ? 0 : (Math.sqrt((r * r) - (dy * dy)).toNumber() - 6);
    }

    hidden function fit(dc, text, font, maxWidth) {
        if (dc.getTextWidthInPixels(text, font) <= maxWidth) {
            return text;
        }
        while (text.length() > 0 && dc.getTextWidthInPixels(text + ".", font) > maxWidth) {
            text = text.substring(0, text.length() - 1);
        }
        return text + ".";
    }

    function onUpdate(dc) {
        var state = _client.getState();
        var cx = dc.getWidth() / 2;
        // On these watches xtiny/tiny/small are one 12 px face; medium is the largest that fits four rows
        var small = Gfx.FONT_TINY;
        var hS = dc.getFontHeight(small);
        var bodyTop = hS + 4;
        var footY = dc.getHeight() - hS - 2;
        var total = state.departures.size();
        var rows = _detail ? 4 : 3;
        var offset = 0;
        if (_detail && total > rows) {
            offset = (state.scrollOffset > total - rows) ? (total - rows) : state.scrollOffset;
            state.scrollOffset = offset;
        }

        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        // Title: stop name, then the favourite's own filters or the GPS distance.
        // The name is shortened before the suffix, unless the suffix is very long.
        var headW = 2 * halfWidth(dc, 2 + (hS / 5), 2 + hS);
        var suffix = _client.titleTag() + ((state.distanceMeters != null) ? (" " + state.distanceMeters + "m") : "");
        var room = headW - dc.getTextWidthInPixels(suffix, small);
        dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, 2, small, (room > headW / 2) ? (fit(dc, state.stopName, small, room) + suffix)
            : fit(dc, state.stopName + suffix, small, headW), Gfx.TEXT_JUSTIFY_CENTER);

        // Footer: global line filter, then status, scroll position or the START hint
        var lines = _client.footerTag();
        var footer = (lines.length() > 0) ? "START" : (_detail ? "START: menu" : "START: more");
        var failed = (state.status == :error) && total > 0;
        if (state.status == :loading) {
            footer = "Updating";
        } else if (failed) {
            footer = state.errorMessage;
        } else if (offset + rows <= total && _detail) {
            footer = (offset + 1) + "-" + (offset + rows) + "/" + total;
        }
        if (lines.length() > 0) {
            footer = lines + " | " + footer;
        }
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        var lw = halfWidth(dc, bodyTop, bodyTop);
        dc.drawLine(cx - lw, bodyTop - 1, cx + lw, bodyTop - 1);
        lw = halfWidth(dc, footY, footY);
        dc.drawLine(cx - lw, footY - 1, cx + lw, footY - 1);
        dc.setColor(failed ? Gfx.COLOR_ORANGE : Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, footY, small, fit(dc, footer, small, 2 * halfWidth(dc, footY, footY + ((hS * 4) / 5))), Gfx.TEXT_JUSTIFY_CENTER);

        var bodyH = footY - 2 - bodyTop;
        if (total == 0) {
            var msg = (state.status == :error) ? state.errorMessage : ((state.status == :ready) ? "No departures" : "Fetching...");
            dc.setColor((state.status == :error) ? Gfx.COLOR_ORANGE : Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, bodyTop + ((bodyH - hS) / 2), small, fit(dc, msg, small, dc.getWidth() - 24), Gfx.TEXT_JUSTIFY_CENTER);
            return;
        }

        var font = Gfx.FONT_MEDIUM;
        var rowH = bodyH / rows;
        var inset = (rowH - dc.getFontHeight(font)) / 2;
        // Width is set by the first and last row, where the screen is narrowest
        var half = halfWidth(dc, bodyTop + inset, bodyTop + (rows * rowH) - inset);
        var left = cx - half;
        var right = cx + half;
        // Badge as wide as the widest visible line code
        var pillW = 24;
        for (var r = 0; r < rows && (offset + r) < total; r++) {
            var cw = dc.getTextWidthInPixels(state.departures[offset + r].lineCode, small) + 8;
            pillW = (cw > 46) ? 46 : ((cw > pillW) ? cw : pillW);
        }

        var now = _client.serverNow();
        for (var r = 0; r < rows && (offset + r) < total; r++) {
            var item = state.departures[offset + r];
            var rowY = bodyTop + (r * rowH);

            // Line number on the mode's colour
            dc.setColor(item.modeColor, Gfx.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(left, rowY + ((rowH - hS - 2) / 2), pillW, hS + 2, 4);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(left + (pillW / 2), rowY + ((rowH - hS) / 2), small, fit(dc, item.lineCode, small, pillW - 4), Gfx.TEXT_JUSTIFY_CENTER);

            // Countdown on Entur's clock, or the wall-clock time when that is unknown
            var live = LegacyParse.isCountdown(item, now);
            var countdown = live ? item.formatCountdown() : item.wall;
            dc.setColor((live && item.minutesUntil <= 2) ? Gfx.COLOR_GREEN : Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(right, rowY + inset, font, countdown, Gfx.TEXT_JUSTIFY_RIGHT);

            // Green dot = live estimate, yellow = timetable only
            var dotX = right - dc.getTextWidthInPixels(countdown, font) - 7;
            dc.setColor(item.isRealtime ? Gfx.COLOR_GREEN : Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
            dc.fillCircle(dotX, rowY + (rowH / 2), 3);

            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(left + pillW + 5, rowY + inset, font, fit(dc, item.destination, font, dotX - 12 - left - pillW), Gfx.TEXT_JUSTIFY_LEFT);
        }
    }
}
