import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
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

        var hXtiny = dc.getFontHeight(Graphics.FONT_XTINY);
        var hTiny = dc.getFontHeight(Graphics.FONT_TINY);
        var bezelPad = (width * 25) / 1000;
        if (bezelPad < 6) {
            bezelPad = 6;
        }
        var vGap = (height * 15) / 1000;
        if (vGap < 3) {
            vGap = 3;
        }

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // 1. Header: Active stop mode badge + distance
        var modeY = (height * 6) / 100;
        var modeHalfW = computeChordHalfWidth(modeY + (hXtiny / 8), modeY + hXtiny, width, height, bezelPad);
        var modeBadge = self.getStopSourceLabel();
        if (state.distanceMeters != null) {
            modeBadge = modeBadge + " • " + state.distanceMeters.toString() + "m";
        }
        if (state.status == :loading) {
            modeBadge = modeBadge + " • SYNC";
        }
        modeBadge = self.fitTextToWidth(dc, modeBadge, Graphics.FONT_XTINY, modeHalfW * 2);
        dc.setColor(0x00AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, modeY, Graphics.FONT_XTINY, modeBadge, Graphics.TEXT_JUSTIFY_CENTER);

        // 2. Stop Name (fit to circular chord width at titleY)
        var titleY = modeY + ((hXtiny * 8) / 10);
        var titleHalfW = computeChordHalfWidth(titleY + (hTiny / 8), titleY + hTiny, width, height, bezelPad);
        var stopTitle = self.fitTextToWidth(dc, state.stopName, Graphics.FONT_TINY, titleHalfW * 2);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, titleY, Graphics.FONT_TINY, stopTitle, Graphics.TEXT_JUSTIFY_CENTER);

        // Header divider
        var headerDivY = titleY + hTiny + vGap;
        var headerDivHalfW = computeChordHalfWidth(headerDivY, headerDivY, width, height, bezelPad);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(centerX - headerDivHalfW, headerDivY, centerX + headerDivHalfW, headerDivY);

        // 4. Footer layout (anchored from bottom so body fills all remaining vertical space)
        var bottomPad = (height * 9) / 100;
        var footerY = height - bottomPad - hXtiny;
        var footerDivY = footerY - vGap;
        var footerDivHalfW = computeChordHalfWidth(footerDivY, footerDivY, width, height, bezelPad);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(centerX - footerDivHalfW, footerDivY, centerX + footerDivHalfW, footerDivY);

        var total = state.departures.size();
        var sortTag = self._client.getSortByModeFirst() ? "Mode+Time" : "Time Only";
        var footer = sortTag + " • Hold UP: Menu";
        if (total > VISIBLE_ROWS) {
            var endIdx = state.scrollOffset + VISIBLE_ROWS;
            if (endIdx > total) {
                endIdx = total;
            }
            footer = sortTag + " (" + (state.scrollOffset + 1).toString() + "-" + endIdx.toString() + "/" + total.toString() + ")";
        }
        var footerHalfW = computeChordHalfWidth(footerY, footerY + ((hXtiny * 85) / 100), width, height, bezelPad);
        if (dc.getTextWidthInPixels(footer, Graphics.FONT_XTINY) > (footerHalfW * 2) && total <= VISIBLE_ROWS) {
            footer = sortTag + " • UP: Menu";
        }
        footer = self.fitTextToWidth(dc, footer, Graphics.FONT_XTINY, footerHalfW * 2);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, footerY, Graphics.FONT_XTINY, footer, Graphics.TEXT_JUSTIFY_CENTER);

        // 3. Body: Departures list or status message
        var bodyTop = headerDivY + vGap;
        var bodyBottom = footerDivY - vGap;
        var bodyHeight = bodyBottom - bodyTop;
        if (total == 0) {
            var msg = "No departures";
            var msgColor = Graphics.COLOR_LT_GRAY;
            if (state.status == :loading) {
                msg = "Fetching Entur...";
            } else if (state.status == :error) {
                msg = state.errorMessage;
                msgColor = Graphics.COLOR_ORANGE;
            }
            var msgFont = Graphics.FONT_SMALL;
            var msgH = dc.getFontHeight(msgFont);
            var msgY = bodyTop + ((bodyHeight - msgH) / 2);
            var msgHalfW = computeChordHalfWidth(msgY, msgY + msgH, width, height, bezelPad);
            if (dc.getTextWidthInPixels(msg, msgFont) > (msgHalfW * 2)) {
                msgFont = Graphics.FONT_TINY;
                msgH = hTiny;
                msgY = bodyTop + ((bodyHeight - msgH) / 2);
                msgHalfW = computeChordHalfWidth(msgY, msgY + msgH, width, height, bezelPad);
            }
            msg = self.fitTextToWidth(dc, msg, msgFont, msgHalfW * 2);
            dc.setColor(msgColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, msgY, msgFont, msg, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            var rowHeight = bodyHeight / VISIBLE_ROWS;
            var pillH = hXtiny + ((height >= 360) ? 8 : 6);
            if (pillH > rowHeight - 4) {
                pillH = rowHeight - 4;
            }
            var rowInkPad = (rowHeight - pillH) / 2;
            if (rowInkPad < 0) {
                rowInkPad = 0;
            }
            var firstRowTop = bodyTop + rowInkPad;
            var lastRowBot = bodyTop + (VISIBLE_ROWS * rowHeight) - rowInkPad;
            var rowHalfW = computeChordHalfWidth(firstRowTop, lastRowBot, width, height, bezelPad);

            var scrollReserve = (total > VISIBLE_ROWS) ? ((width >= 360) ? 10 : 6) : 0;
            var rowLeftX = centerX - rowHalfW;
            var rowRightX = centerX + rowHalfW - scrollReserve;
            var availRowW = rowRightX - rowLeftX;

            var pillPadX = (hXtiny * 30) / 100;
            if (pillPadX < 4) {
                pillPadX = 4;
            }
            var minPillW = (availRowW * 22) / 100;
            var maxPillW = (availRowW * 36) / 100;
            var pillW = self.computePillWidth(dc, state.departures, state.scrollOffset, pillPadX, minPillW, maxPillW);

            var rowLayout = {
                :rowHeight => rowHeight,
                :rowLeftX => rowLeftX,
                :rowRightX => rowRightX,
                :pillW => pillW,
                :pillH => pillH,
                :hXtiny => hXtiny,
                :hTiny => hTiny,
                :screenWidth => width
            } as Dictionary<Symbol, Number>;

            for (var r = 0; r < VISIBLE_ROWS; r++) {
                var idx = state.scrollOffset + r;
                if (idx >= total) {
                    break;
                }
                self.drawDepartureRow(
                    dc,
                    state.departures[idx],
                    bodyTop + (r * rowHeight),
                    rowLayout
                );
            }

            // Draw right-edge scroll indicator if more than VISIBLE_ROWS
            if (total > VISIBLE_ROWS) {
                self.drawScrollIndicator(dc, state.scrollOffset, total, rowRightX + scrollReserve, bodyTop, bodyHeight, width);
            }
        }
    }

    public static function computeChordHalfWidth(
        yTop as Number,
        yBottom as Number,
        width as Number,
        height as Number,
        margin as Number
    ) as Number {
        var centerY = height / 2;
        var radius = ((width < height) ? width : height) / 2;
        var effRadius = radius - margin;
        if (effRadius <= 0) {
            return 0;
        }
        var dyTop = (yTop < centerY) ? (centerY - yTop) : (yTop - centerY);
        var dyBot = (yBottom < centerY) ? (centerY - yBottom) : (yBottom - centerY);
        var dy = (dyTop > dyBot) ? dyTop : dyBot;
        if (dy >= effRadius) {
            return 0;
        }
        return Math.sqrt((effRadius * effRadius) - (dy * dy)).toNumber();
    }

    private function fitTextToWidth(
        dc as Graphics.Dc,
        text as String,
        font as Graphics.FontType,
        maxWidth as Number
    ) as String {
        if (maxWidth <= 0) {
            return "";
        }
        if (dc.getTextWidthInPixels(text, font) <= maxWidth) {
            return text;
        }
        var truncated = text;
        while (truncated.length() > 0 && dc.getTextWidthInPixels(truncated + ".", font) > maxWidth) {
            truncated = truncated.substring(0, truncated.length() - 1);
        }
        if (truncated.length() > 0) {
            return truncated + ".";
        }
        return "";
    }

    private function resolveBadgeText(
        dc as Graphics.Dc,
        item as DepartureModel.DepartureItem,
        maxBadgeTextW as Number
    ) as String {
        var fullBadge = item.modeLabel + " " + item.lineCode;
        if (dc.getTextWidthInPixels(fullBadge, Graphics.FONT_XTINY) <= maxBadgeTextW) {
            return fullBadge;
        }
        return self.fitTextToWidth(dc, item.lineCode, Graphics.FONT_XTINY, maxBadgeTextW);
    }

    private function computePillWidth(
        dc as Graphics.Dc,
        departures as Array<DepartureModel.DepartureItem>,
        scrollOffset as Number,
        pillPadX as Number,
        minPillW as Number,
        maxPillW as Number
    ) as Number {
        var total = departures.size();
        var maxBadgeTextW = maxPillW - (pillPadX * 2);
        var neededW = minPillW;
        for (var r = 0; r < VISIBLE_ROWS; r++) {
            var idx = scrollOffset + r;
            if (idx >= total) {
                break;
            }
            var badge = self.resolveBadgeText(dc, departures[idx], maxBadgeTextW);
            var w = dc.getTextWidthInPixels(badge, Graphics.FONT_XTINY) + (pillPadX * 2);
            if (w > neededW) {
                neededW = w;
            }
        }
        if (neededW > maxPillW) {
            return maxPillW;
        }
        return neededW;
    }

    private function drawDepartureRow(
        dc as Graphics.Dc,
        item as DepartureModel.DepartureItem,
        rowY as Number,
        layout as Dictionary<Symbol, Number>
    ) as Void {
        var rowHeight = layout[:rowHeight] as Number;
        var rowLeftX = layout[:rowLeftX] as Number;
        var rowRightX = layout[:rowRightX] as Number;
        var pillW = layout[:pillW] as Number;
        var pillH = layout[:pillH] as Number;
        var hXtiny = layout[:hXtiny] as Number;
        var hTiny = layout[:hTiny] as Number;
        var screenWidth = layout[:screenWidth] as Number;

        // Mode + Line badge pill on the left
        var pillX = rowLeftX;
        var pillY = rowY + ((rowHeight - pillH) / 2);
        var pillRadius = pillH / 5;
        if (pillRadius < 4) {
            pillRadius = 4;
        }

        dc.setColor(item.modeColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(pillX, pillY, pillW, pillH, pillRadius);

        var badgeText = self.resolveBadgeText(dc, item, pillW - 6);
        var badgeY = pillY + ((pillH - hXtiny) / 2);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            pillX + (pillW / 2),
            badgeY,
            Graphics.FONT_XTINY,
            badgeText,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // Countdown text on the right (measured first so dot and destination never collide)
        var countdownText = item.formatCountdown();
        var countdownW = dc.getTextWidthInPixels(countdownText, Graphics.FONT_TINY);
        var textY = rowY + ((rowHeight - hTiny) / 2);
        var timeColor = (item.minutesUntil <= 2) ? 0x00FF00 : Graphics.COLOR_WHITE;
        dc.setColor(timeColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            rowRightX,
            textY,
            Graphics.FONT_TINY,
            countdownText,
            Graphics.TEXT_JUSTIFY_RIGHT
        );

        // Real-time indicator dot (Green = live SIRI, Yellow = scheduled)
        var dotRadius = (screenWidth >= 360) ? 5 : 3;
        var dotGap = (screenWidth >= 360) ? 10 : 6;
        var dotX = rowRightX - countdownW - dotGap - dotRadius;
        var dotY = rowY + (rowHeight / 2);
        var rtColor = item.isRealtime ? 0x00FF00 : 0xFFAA00;
        dc.setColor(rtColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(dotX, dotY, dotRadius);

        // Destination text fitted between pill and real-time dot
        var colGap = (screenWidth >= 360) ? 10 : 6;
        var destX = pillX + pillW + colGap;
        var maxDestW = (dotX - dotRadius - colGap) - destX;
        var dest = self.fitTextToWidth(dc, item.destination, Graphics.FONT_TINY, maxDestW);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(destX, textY, Graphics.FONT_TINY, dest, Graphics.TEXT_JUSTIFY_LEFT);
    }

    private function drawScrollIndicator(
        dc as Graphics.Dc,
        offset as Number,
        total as Number,
        trackX as Number,
        bodyTop as Number,
        bodyHeight as Number,
        screenWidth as Number
    ) as Void {
        var trackY = bodyTop + (bodyHeight / 8);
        var trackH = (bodyHeight * 3) / 4;
        if (trackH < 12) {
            return;
        }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(trackX, trackY, trackX, trackY + trackH);

        var maxOffset = total - VISIBLE_ROWS;
        if (maxOffset < 1) {
            maxOffset = 1;
        }
        var thumbH = trackH / 4;
        if (thumbH < 10) {
            thumbH = 10;
        }
        var thumbW = (screenWidth >= 360) ? 4 : 3;
        var thumbY = trackY + ((offset * (trackH - thumbH)) / maxOffset);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(trackX - (thumbW / 2), thumbY, thumbW, thumbH);
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
        return "AVGANG";
    }
}
