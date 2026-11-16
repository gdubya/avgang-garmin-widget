using Toybox.Application as App;
using Toybox.Communications as Comm;
using Toybox.Lang as Lang;
using Toybox.Position as Position;
using Toybox.System as Sys;
using Toybox.Time as Time;
using Toybox.WatchUi as Ui;

// Entur client for Connect IQ 1.x watches: the same phone settings and filter
// rules as EnturApiClient, stored with AppBase.getProperty/setProperty, one
// request in flight at a time. Countdowns use Entur's clock (offset = server
// time - Time.now()), never the watch's date or time zone.
class LegacyClient {

    const GRAPHQL_URL = "https://api.entur.io/journey-planner/v3/graphql";
    const GEOCODER_URL = "https://api.entur.io/geocoder/v1/autocomplete";
    const LINE_CACHE_TTL_SEC = 604800;
    const CLOCK_MAX_AGE_SEC = 600;
    // A request with no callback after this long is considered lost
    const BUSY_TIMEOUT_SEC = 45;

    // GPS source without a position yet: the view retries every tick
    var gpsWait = false;

    hidden var _state;
    // Entur line ids behind _state.routeFilter
    hidden var _lineIds = [];
    // Favourite (1-3) behind the current request, 0 for GPS Nearest and Pinned
    hidden var _fav = 0;
    // True when _state.routeFilter is the favourite's own line list
    hidden var _favLines = false;
    hidden var _busySince = 0;
    hidden var _again = false;
    // Server epoch - watch epoch, null until Entur has told us its time
    hidden var _offset = null;
    hidden var _offsetAt = 0;

    function initialize(state) {
        _state = state;
    }

    function getState() {
        return _state;
    }

    function prop(key) {
        return App.getApp().getProperty(key);
    }

    function setProp(key, value) {
        App.getApp().setProperty(key, value);
    }

    // A text setting, trimmed; "" when unset
    function text(key) {
        var v = prop(key);
        return (v instanceof Lang.String) ? DepartureModel.trimSpaces(v) : "";
    }

    function codes(key) {
        return DepartureModel.parseRouteFilter(text(key));
    }

    function getActiveStopMode() {
        var mode = prop("activeStopMode");
        return (mode instanceof Lang.Number) ? mode : DepartureModel.MODE_FAV_1;
    }

    function setActiveStopMode(mode) {
        setProp("activeStopMode", mode);
        reload();
    }

    // true unless the setting is switched off ("sortByModeFirst", "routeFilterEnabled")
    function isOn(key) {
        return prop(key) != false;
    }

    function toggle(key) {
        setProp(key, !isOn(key));
        reload();
    }

    // Favourite (1-3) behind the active stop source, or 0 for GPS Nearest and Pinned
    function getActiveFavorite() {
        var mode = getActiveStopMode();
        if (mode == DepartureModel.MODE_GPS || (mode == DepartureModel.MODE_PINNED && text("pinnedStopId").length() > 0)) {
            return 0;
        }
        return (mode == DepartureModel.MODE_FAV_2 || mode == DepartureModel.MODE_FAV_3) ? mode : 1;
    }

    // A favourite's own filters as a suffix: " (bus)", " (21)", " (bus 21)" or ""
    function favTag(n) {
        var tag = DepartureModel.trimSpaces(
            DepartureModel.joinCodes(DepartureModel.parseTransportModes(text("stopModes" + n))) + " " +
            DepartureModel.joinCodes(codes("stopLines" + n)));
        return (tag.length() > 0) ? (" (" + tag + ")") : "";
    }

    // Favourite n's remembered stop { q: text entered, id, n: name }; null once the text has changed
    hidden function favStop(n) {
        var cached = prop("fav" + n);
        return (cached instanceof Lang.Dictionary && text("stopQuery" + n).equals(cached["q"])) ? cached : null;
    }

    // The stop's name once it has loaded, else the text from the phone app
    function getFavName(n) {
        var query = text("stopQuery" + n);
        if (favStop(n) != null) {
            return favStop(n)["n"];
        }
        return (query.length() == 0 || query.find("NSR:StopPlace:") == 0) ? ("Fav " + n) : query;
    }

    function titleTag() {
        return (_fav > 0) ? favTag(_fav) : "";
    }

    // "Lines 17,31" when the global Favorite Lines are behind the board
    function footerTag() {
        return (_favLines || _state.routeFilter.size() == 0) ? "" : ("Lines " + DepartureModel.joinCodes(_state.routeFilter));
    }

    function pinCurrentStop() {
        if (_state.stopId.length() > 0) {
            setProp("pinnedStopId", _state.stopId);
            setProp("pinnedStopName", _state.stopName);
            setActiveStopMode(DepartureModel.MODE_PINNED);
        }
    }

    // Server "now" as UTC epoch seconds, or null when unknown
    function serverNow() {
        return (_offset == null) ? null : (Time.now().value() + _offset);
    }

    function recalc() {
        if (_offset != null) {
            _state.recalculateCountdowns(serverNow());
        }
    }

    hidden function isBusy() {
        return (Time.now().value() - _busySince).abs() < BUSY_TIMEOUT_SEC;
    }

    // Timer refresh: skipped while a request is in flight
    function autoRefresh() {
        if (!isBusy()) {
            refreshDepartures();
        }
    }

    // The stop source, a filter or a setting changed: drop the board and fetch again
    function reload() {
        _state.departures = [];
        _state.stopId = "";
        _state.scrollOffset = 0;
        refreshDepartures();
    }

    function refreshDepartures() {
        _again = isBusy();
        _state.status = :loading;
        Ui.requestUpdate();
        if (_again) {
            return; // re-run when the pending reply arrives; that reply is dropped
        }

        // As in EnturApiClient: a favourite's own lines replace the global list,
        // its modes always apply, GPS Nearest and Pinned only get the global list.
        _fav = getActiveFavorite();
        var lines = codes("stopLines" + _fav);
        _favLines = lines.size() > 0;
        if (!_favLines && isOn("routeFilterEnabled")) {
            lines = codes("routeFilter");
        }
        _state.routeFilter = lines;
        _state.modeFilter = DepartureModel.parseTransportModes(text("stopModes" + _fav));
        if (_state.stopId.length() == 0) {
            // Nothing loaded yet: title the screen with the source, not "Avgang"
            _state.stopName = (_fav > 0) ? getFavName(_fav) : ((getActiveStopMode() == DepartureModel.MODE_GPS) ? "GPS" : text("pinnedStopName"));
        }

        // Line codes -> Entur line ids, cached for a week for the current list
        _lineIds = [];
        var cached = prop("lineids");
        if (lines.size() == 0) {
            loadStop();
        } else if (cached instanceof Lang.Dictionary && DepartureModel.joinCodes(lines).equals(cached["k"]) &&
                (Time.now().value() - cached["t"]).abs() < LINE_CACHE_TTL_SEC) {
            _lineIds = cached["ids"];
            loadStop();
        } else {
            send(GRAPHQL_URL, LegacyParse.linesBody(lines), method(:onLinesResponse));
        }
    }

    hidden function loadStop() {
        if (_fav == 0 && getActiveStopMode() == DepartureModel.MODE_GPS) {
            var info = Position.getInfo();
            if (info.position != null && info.accuracy != Position.QUALITY_NOT_AVAILABLE) {
                var c = info.position.toDegrees();
                gpsWait = false;
                send(GRAPHQL_URL, LegacyParse.nearestBody(c[0], c[1], _lineIds, needClock()), method(:onResponse));
            } else {
                if (!gpsWait) {
                    gpsWait = true;
                    Position.enableLocationEvents(Position.LOCATION_ONE_SHOT, method(:onPosition));
                }
                fail("Waiting for GPS");
            }
            return;
        }
        _state.distanceMeters = null;
        var stop = text("pinnedStopId");
        if (_fav > 0) {
            // A favourite is a name or an NSR id; a name is looked up once and remembered
            stop = (favStop(_fav) != null) ? favStop(_fav)["id"] : text("stopQuery" + _fav);
        }
        if (stop.find("NSR:StopPlace:") == 0) {
            fetchStop(stop);
        } else if (stop.length() > 0) {
            send(GEOCODER_URL, { "text" => stop, "size" => "1", "layers" => "venue" }, method(:onGeocoderResponse));
        } else {
            fail("Set stop in phone app");
        }
    }

    hidden function fetchStop(stopId) {
        send(GRAPHQL_URL, LegacyParse.stopBody(stopId, _lineIds, _state.modeFilter, needClock()), method(:onResponse));
    }

    hidden function needClock() {
        return _offset == null || (Time.now().value() - _offsetAt).abs() > CLOCK_MAX_AGE_SEC;
    }

    hidden function send(url, params, callback) {
        Sys.println("request: " + ((params["variables"] != null) ? params["variables"] : params));
        _busySince = Time.now().value();
        var name = text("clientName");
        var headers = { "ET-Client-Name" => (name.length() > 0) ? name : "personal-garmin-avgang-widget" };
        var post = url.equals(GRAPHQL_URL);
        if (post) {
            headers["Content-Type"] = Comm.REQUEST_CONTENT_TYPE_JSON;
        }
        Comm.makeWebRequest(url, params, {
            :method => post ? Comm.HTTP_REQUEST_METHOD_POST : Comm.HTTP_REQUEST_METHOD_GET,
            :headers => headers,
            :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, callback);
    }

    hidden function fail(msg) {
        Sys.println("error: " + msg);
        _state.status = :error;
        _state.errorMessage = msg;
        Ui.requestUpdate();
    }

    // Common start of the reply callbacks; false when there is nothing to use
    hidden function arrived(code, data) {
        Sys.println("reply: " + code);
        _busySince = 0;
        if (_again) {
            refreshDepartures();
        } else if (code == 200 && data instanceof Lang.Dictionary) {
            return true;
        } else if (code == -104 || code == -2 || code == -1) {
            fail("No phone link");
        } else if (code == -402 || code == -403) {
            fail("Reply too big");
        } else if (code == -300) {
            fail("Timed out");
        } else {
            fail(((code < 0) ? "Net error " : "HTTP ") + code);
        }
        return false;
    }

    // Callbacks are typed because the compiler type-checks callbacks passed to Toybox
    function onPosition(info as Position.Info) as Void {
        autoRefresh();
    }

    function onLinesResponse(code as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        if (arrived(code, data)) {
            var ids = LegacyParse.lineIds(data);
            if (ids == null || ids.size() == 0) {
                fail("Unknown line(s)");
                return;
            }
            setProp("lineids", { "k" => DepartureModel.joinCodes(_state.routeFilter), "t" => Time.now().value(), "ids" => ids });
            _lineIds = ids;
            loadStop();
        }
    }

    function onGeocoderResponse(code as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        if (arrived(code, data)) {
            var id = LegacyParse.geocodedStopId(data);
            if (id == null) {
                fail("Stop not found");
            } else {
                fetchStop(id);
            }
        }
    }

    function onResponse(code as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        if (arrived(code, data)) {
            var now = Time.now().value();
            var server = LegacyParse.serverEpoch(data);
            if (server != null) {
                _offset = server - now;
                _offsetAt = now;
            }
            if (!LegacyParse.parse(data, _state, serverNow(), isOn("sortByModeFirst"))) {
                fail("No stop found");
                return;
            }
            _state.lastUpdatedEpoch = now; // watch time: only ever compared with Time.now()
            if (_fav > 0 && favStop(_fav) == null) {
                setProp("fav" + _fav, { "q" => text("stopQuery" + _fav), "id" => _state.stopId, "n" => _state.stopName });
            }
            Ui.requestUpdate();
        }
    }
}
