import Toybox.Lang;
import Toybox.Time;

(:glance)
module DepartureModel {

    enum StopSourceMode {
        MODE_GPS = 0,
        MODE_FAV_1 = 1,
        MODE_FAV_2 = 2,
        MODE_FAV_3 = 3,
        MODE_PINNED = 4
    }

    (:glance)
    class DepartureItem {
        public var transportMode as String;
        public var modeLabel as String;
        public var modeColor as Number;
        public var lineCode as String;
        public var destination as String;
        public var expectedEpoch as Number;
        public var minutesUntil as Number;
        public var isRealtime as Boolean;

        public function initialize(
            transportMode as String,
            lineCode as String,
            destination as String,
            expectedEpoch as Number,
            nowEpoch as Number,
            isRealtime as Boolean
        ) {
            self.transportMode = transportMode.toLower();
            self.modeLabel = DepartureItem.resolveModeLabel(self.transportMode);
            self.modeColor = DepartureItem.resolveModeColor(self.transportMode);
            self.lineCode = lineCode;
            self.destination = destination;
            self.expectedEpoch = expectedEpoch;
            self.isRealtime = isRealtime;
            self.minutesUntil = DepartureItem.computeMinutesUntil(expectedEpoch, nowEpoch);
        }

        public static function computeMinutesUntil(expectedEpoch as Number, nowEpoch as Number) as Number {
            var diffSec = expectedEpoch - nowEpoch;
            if (diffSec <= 30) {
                return 0;
            }
            return (diffSec / 60).toNumber();
        }

        public static function resolveModeLabel(mode as String) as String {
            if (mode.equals("bus") || mode.equals("coach")) {
                return "BUS";
            } else if (mode.equals("metro")) {
                return "T-B";
            } else if (mode.equals("tram")) {
                return "TRK";
            } else if (mode.equals("rail")) {
                return "TOG";
            } else if (mode.equals("water")) {
                return "BAT";
            }
            return "KOL";
        }

        // Uses standard 64-color palette compatible RGB hex constants for Garmin fēnix 6S
        public static function resolveModeColor(mode as String) as Number {
            if (mode.equals("bus") || mode.equals("coach")) {
                return 0xFF0000; // Ruter Bus Red
            } else if (mode.equals("metro")) {
                return 0xFF5500; // Ruter T-bane Orange
            } else if (mode.equals("tram")) {
                return 0x00AAFF; // Ruter Trikk Light Blue
            } else if (mode.equals("rail")) {
                return 0x00AA00; // Train Green
            } else if (mode.equals("water")) {
                return 0xAA00FF; // Ferry Purple
            }
            return 0xAAAAAA;
        }

        public function formatCountdown() as String {
            if (self.minutesUntil <= 0) {
                return "Now";
            }
            return self.minutesUntil.toString() + "m";
        }
    }

    (:glance)
    class StopBoardState {
        public var stopId as String = "";
        public var stopName as String = "Avgang";
        public var distanceMeters as Number or Null = null;
        public var departures as Array<DepartureItem> = [] as Array<DepartureItem>;
        public var scrollOffset as Number = 0;
        public var status as Symbol = :idle;
        public var errorMessage as String = "";
        public var lastUpdatedEpoch as Number = 0;

        public function initialize() {
        }

        public function recalculateCountdowns(nowEpoch as Number) as Void {
            var active = [] as Array<DepartureItem>;
            for (var i = 0; i < self.departures.size(); i++) {
                var item = self.departures[i];
                // Keep departures that haven't left more than 45 seconds ago
                if (item.expectedEpoch >= (nowEpoch - 45)) {
                    item.minutesUntil = DepartureItem.computeMinutesUntil(item.expectedEpoch, nowEpoch);
                    active.add(item);
                }
            }
            self.departures = active;
            if (self.scrollOffset >= self.departures.size() && self.departures.size() > 0) {
                self.scrollOffset = self.departures.size() - 1;
            }
        }

        // Sorts departures chronologically first, then groups by transportMode if sortByModeFirst is true
        public function sortDepartures(sortByModeFirst as Boolean) as Void {
            var count = self.departures.size();
            if (count <= 1) {
                return;
            }

            // 1. Insertion sort chronologically by expectedEpoch ascending
            for (var i = 1; i < count; i++) {
                var key = self.departures[i];
                var j = i - 1;
                while (j >= 0 && self.departures[j].expectedEpoch > key.expectedEpoch) {
                    self.departures[j + 1] = self.departures[j];
                    j = j - 1;
                }
                self.departures[j + 1] = key;
            }

            if (!sortByModeFirst) {
                return;
            }

            // 2. Group by transportMode ordered by whichever mode has the earliest upcoming departure
            var modeOrder = [] as Array<String>;
            for (var i = 0; i < count; i++) {
                var mode = self.departures[i].transportMode;
                var seen = false;
                for (var m = 0; m < modeOrder.size(); m++) {
                    if (modeOrder[m].equals(mode)) {
                        seen = true;
                        break;
                    }
                }
                if (!seen) {
                    modeOrder.add(mode);
                }
            }

            var grouped = [] as Array<DepartureItem>;
            for (var m = 0; m < modeOrder.size(); m++) {
                var targetMode = modeOrder[m];
                for (var i = 0; i < count; i++) {
                    if (self.departures[i].transportMode.equals(targetMode)) {
                        grouped.add(self.departures[i]);
                    }
                }
            }
            self.departures = grouped;
        }
    }
}
