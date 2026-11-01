import Toybox.Application;
import Toybox.Application.Properties;
import Toybox.Application.Storage;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
import DepartureModel;

(:glance)
class EnturApiClient {

    public static const GRAPHQL_URL = "https://api.entur.io/journey-planner/v3/graphql";
    public static const GEOCODER_URL = "https://api.entur.io/geocoder/v1/autocomplete";
    public static const MAX_DEPARTURES = 8;

    private var _state as DepartureModel.StopBoardState;
    private var _pendingQueryName as String = "";

    public function initialize(state as DepartureModel.StopBoardState) {
        self._state = state;
    }

    public function getState() as DepartureModel.StopBoardState {
        return self._state;
    }

    public function getActiveStopMode() as Number {
        var mode = Properties.getValue("activeStopMode");
        if (mode instanceof Number) {
            return mode;
        }
        return DepartureModel.MODE_FAV_1;
    }

    public function setActiveStopMode(mode as Number) as Void {
        Properties.setValue("activeStopMode", mode);
    }

    public function getSortByModeFirst() as Boolean {
        var val = Properties.getValue("sortByModeFirst");
        if (val instanceof Boolean) {
            return val;
        }
        return true;
    }

    public function setSortByModeFirst(enabled as Boolean) as Void {
        Properties.setValue("sortByModeFirst", enabled);
        self._state.sortDepartures(enabled);
        WatchUi.requestUpdate();
    }

    public function pinCurrentStop() as Boolean {
        if (self._state.stopId.length() == 0) {
            return false;
        }
        Storage.setValue("pinnedStopId", self._state.stopId);
        Storage.setValue("pinnedStopName", self._state.stopName);
        self.setActiveStopMode(DepartureModel.MODE_PINNED);
        return true;
    }

    public function getClientHeaderName() as String {
        var clientName = Properties.getValue("clientName");
        if (clientName instanceof String && clientName.length() > 0) {
            return clientName;
        }
        return "personal-garmin-ruter-widget";
    }

    public function refreshDepartures() as Void {
        self._state.status = :loading;
        self._state.errorMessage = "";
        WatchUi.requestUpdate();

        var mode = self.getActiveStopMode();
        if (mode == DepartureModel.MODE_GPS) {
            self.requestGpsNearest();
            return;
        }

        if (mode == DepartureModel.MODE_PINNED) {
            var pinnedId = Storage.getValue("pinnedStopId");
            if (pinnedId instanceof String && pinnedId.length() > 0) {
                self._state.distanceMeters = null;
                self.fetchByStopId(pinnedId);
                return;
            }
            // Fall back to Favorite 1 if nothing is pinned yet
            mode = DepartureModel.MODE_FAV_1;
        }

        var propKey = "stopQuery1";
        if (mode == DepartureModel.MODE_FAV_2) {
            propKey = "stopQuery2";
        } else if (mode == DepartureModel.MODE_FAV_3) {
            propKey = "stopQuery3";
        }

        var rawQuery = Properties.getValue(propKey);
        if (!(rawQuery instanceof String) || rawQuery.length() == 0) {
            rawQuery = "NSR:StopPlace:4000";
        }

        self._state.distanceMeters = null;
        if (rawQuery.find("NSR:StopPlace:") == 0) {
            self.fetchByStopId(rawQuery);
        } else {
            var cacheKey = "geocache_" + rawQuery;
            var cachedStopId = Storage.getValue(cacheKey);
            if (cachedStopId instanceof String && cachedStopId.find("NSR:StopPlace:") == 0) {
                self.fetchByStopId(cachedStopId);
            } else {
                self.resolveStopName(rawQuery);
            }
        }
    }

    private function requestGpsNearest() as Void {
        var posInfo = Position.getInfo();
        if (posInfo != null && posInfo.position != null && posInfo.accuracy != Position.QUALITY_NOT_AVAILABLE) {
            var coords = posInfo.position.toDegrees();
            if (coords[0] != 0.0 && coords[0] < 90.0 && coords[0] > -90.0) {
                self.fetchByCoordinates(coords[0], coords[1]);
                return;
            }
        }

        self._state.stopName = "Acquiring GPS...";
        Position.enableLocationEvents(Position.LOCATION_ONE_SHOT, method(:onPositionAcquired));
        WatchUi.requestUpdate();
    }

    public function onPositionAcquired(info as Position.Info) as Void {
        if (info.position != null) {
            var coords = info.position.toDegrees();
            self.fetchByCoordinates(coords[0], coords[1]);
        } else {
            self._state.status = :error;
            self._state.errorMessage = "No GPS fix";
            WatchUi.requestUpdate();
        }
    }

    public function resolveStopName(stopName as String) as Void {
        self._pendingQueryName = stopName;
        var params = {
            "text" => stopName,
            "size" => "1",
            "layers" => "venue"
        };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => {
                "ET-Client-Name" => self.getClientHeaderName()
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(
            GEOCODER_URL,
            params,
            options,
            method(:onReceiveGeocoderResponse)
        );
    }

    public function onReceiveGeocoderResponse(
        responseCode as Number,
        data as Dictionary or String or Null
    ) as Void {
        if (responseCode == 200 && data instanceof Dictionary) {
            var features = data["features"];
            if (features instanceof Array && features.size() > 0) {
                var firstFeature = features[0];
                if (firstFeature instanceof Dictionary) {
                    var props = firstFeature["properties"];
                    if (props instanceof Dictionary) {
                        var id = props["id"];
                        if (id instanceof String && id.find("NSR:StopPlace:") == 0) {
                            if (self._pendingQueryName.length() > 0) {
                                Storage.setValue("geocache_" + self._pendingQueryName, id);
                            }
                            self.fetchByStopId(id);
                            return;
                        }
                    }
                }
            }
            self._state.status = :error;
            self._state.errorMessage = "Stop not found";
        } else {
            self._state.status = :error;
            self._state.errorMessage = "Geocode err " + responseCode.toString();
        }
        WatchUi.requestUpdate();
    }

    public function fetchByStopId(stopId as String) as Void {
        var gql = "{stopPlace(id:\"" + stopId + "\"){id name estimatedCalls(numberOfDepartures:" +
            MAX_DEPARTURES.toString() +
            "){realtime expectedDepartureTime destinationDisplay{frontText}serviceJourney{journeyPattern{line{publicCode transportMode}}}}}}";

        self.sendGraphQlRequest(gql);
    }

    public function fetchByCoordinates(lat as Double or Float, lon as Double or Float) as Void {
        var gql = "{nearest(latitude:" + lat.format("%.5f") +
            ",longitude:" + lon.format("%.5f") +
            ",maximumResults:1,maximumDistance:1000,filterByPlaceTypes:[stopPlace]){edges{node{distance place{... on StopPlace{id name estimatedCalls(numberOfDepartures:" +
            MAX_DEPARTURES.toString() +
            "){realtime expectedDepartureTime destinationDisplay{frontText}serviceJourney{journeyPattern{line{publicCode transportMode}}}}}}}}}}";

        self.sendGraphQlRequest(gql);
    }

    private function sendGraphQlRequest(queryStr as String) as Void {
        var payload = {
            "query" => queryStr
        };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {
                "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                "ET-Client-Name" => self.getClientHeaderName()
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(
            GRAPHQL_URL,
            payload,
            options,
            method(:onReceiveGraphQlResponse)
        );
    }

    public function onReceiveGraphQlResponse(
        responseCode as Number,
        data as Dictionary or String or Null
    ) as Void {
        if (responseCode == 200 && data instanceof Dictionary) {
            var nowEpoch = Time.now().value();
            var parsed = EnturApiClient.parseGraphQlPayload(
                data,
                self._state,
                nowEpoch,
                self.getSortByModeFirst()
            );
            if (!parsed) {
                self._state.status = :error;
                self._state.errorMessage = "Empty stop data";
            }
        } else {
            self._state.status = :error;
            self._state.errorMessage = "HTTP " + responseCode.toString();
        }
        WatchUi.requestUpdate();
    }

    public static function parseGraphQlPayload(
        root as Dictionary,
        state as DepartureModel.StopBoardState,
        nowEpoch as Number,
        sortByModeFirst as Boolean
    ) as Boolean {
        var dataNode = root["data"];
        if (!(dataNode instanceof Dictionary)) {
            return false;
        }

        var stopPlace = dataNode["stopPlace"];
        if (!(stopPlace instanceof Dictionary)) {
            var nearest = dataNode["nearest"];
            if (nearest instanceof Dictionary) {
                var edges = nearest["edges"];
                if (edges instanceof Array && edges.size() > 0) {
                    var edge0 = edges[0];
                    if (edge0 instanceof Dictionary) {
                        var node = edge0["node"];
                        if (node instanceof Dictionary) {
                            var dist = node["distance"];
                            if (dist instanceof Number) {
                                state.distanceMeters = dist;
                            }
                            stopPlace = node["place"];
                        }
                    }
                }
            }
        }

        if (!(stopPlace instanceof Dictionary)) {
            return false;
        }

        var idVal = stopPlace["id"];
        if (idVal instanceof String) {
            state.stopId = idVal;
        }
        var nameVal = stopPlace["name"];
        if (nameVal instanceof String) {
            state.stopName = nameVal;
        }

        var calls = stopPlace["estimatedCalls"];
        var list = [] as Array<DepartureModel.DepartureItem>;
        if (calls instanceof Array) {
            for (var i = 0; i < calls.size(); i++) {
                var call = calls[i];
                if (call instanceof Dictionary) {
                    var item = EnturApiClient.parseEstimatedCall(call, nowEpoch);
                    if (item != null) {
                        list.add(item);
                    }
                }
            }
        }

        state.departures = list;
        state.scrollOffset = 0;
        state.sortDepartures(sortByModeFirst);
        state.lastUpdatedEpoch = nowEpoch;
        state.status = :ready;
        return true;
    }

    public static function parseEstimatedCall(
        call as Dictionary,
        nowEpoch as Number
    ) as DepartureModel.DepartureItem or Null {
        var isoTime = call["expectedDepartureTime"];
        if (!(isoTime instanceof String)) {
            return null;
        }
        var epoch = EnturApiClient.parseIso8601ToEpoch(isoTime);
        if (epoch == null) {
            return null;
        }

        var isRealtime = false;
        var rtVal = call["realtime"];
        if (rtVal instanceof Boolean) {
            isRealtime = rtVal;
        }

        var destText = "";
        var destDisplay = call["destinationDisplay"];
        if (destDisplay instanceof Dictionary) {
            var ft = destDisplay["frontText"];
            if (ft instanceof String) {
                destText = ft;
            }
        }

        var lineCode = "?";
        var transportMode = "bus";
        var sj = call["serviceJourney"];
        if (sj instanceof Dictionary) {
            var jp = sj["journeyPattern"];
            var lineDict = null;
            if (jp instanceof Dictionary) {
                lineDict = jp["line"];
            } else if (sj["line"] instanceof Dictionary) {
                lineDict = sj["line"];
            }
            if (lineDict instanceof Dictionary) {
                var pc = lineDict["publicCode"];
                if (pc instanceof String && pc.length() > 0) {
                    lineCode = pc;
                }
                var tm = lineDict["transportMode"];
                if (tm instanceof String && tm.length() > 0) {
                    transportMode = tm;
                }
            }
        }

        return new DepartureModel.DepartureItem(
            transportMode,
            lineCode,
            destText,
            epoch,
            nowEpoch,
            isRealtime
        );
    }

    // Parses ISO-8601 string e.g. "2026-11-01T16:35:00+01:00" or "2026-11-01T15:35:00Z" into UTC epoch seconds
    public static function parseIso8601ToEpoch(isoStr as String) as Number or Null {
        if (isoStr.length() < 19) {
            return null;
        }

        var year = isoStr.substring(0, 4).toNumber();
        var month = isoStr.substring(5, 7).toNumber();
        var day = isoStr.substring(8, 10).toNumber();
        var hour = isoStr.substring(11, 13).toNumber();
        var minute = isoStr.substring(14, 16).toNumber();
        var second = isoStr.substring(17, 19).toNumber();

        if (year == null || month == null || day == null || hour == null || minute == null || second == null) {
            return null;
        }

        var moment = Gregorian.moment({
            :year => year,
            :month => month,
            :day => day,
            :hour => hour,
            :minute => minute,
            :second => second
        });

        var utcSeconds = moment.value();

        // Parse timezone offset if present after index 19 (e.g. "+01:00", "+02:00", "-05:00")
        if (isoStr.length() >= 25) {
            var signChar = isoStr.substring(19, 20);
            var tzHour = isoStr.substring(20, 22).toNumber();
            var tzMin = isoStr.substring(23, 25).toNumber();
            if (tzHour != null && tzMin != null) {
                var offsetSec = (tzHour * 3600) + (tzMin * 60);
                if (signChar.equals("+")) {
                    utcSeconds = utcSeconds - offsetSec;
                } else if (signChar.equals("-")) {
                    utcSeconds = utcSeconds + offsetSec;
                }
            }
        }

        return utcSeconds;
    }
}
