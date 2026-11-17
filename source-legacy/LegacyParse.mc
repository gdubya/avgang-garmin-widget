using Toybox.Lang as Lang;

// Requests and reply parsing for Connect IQ 1.x watches. No Application/WatchUi
// calls, so it can be unit-tested on a modern profile (see legacy-test.jungle).
// Values go in GraphQL variables and fields are aliased to one letter: no quotes
// inside the query text, and a smaller reply for a 64 kB watch.
module LegacyParse {

    const CALLS = "{r:realtime t:expectedDepartureTime d:destinationDisplay{f:frontText}s:serviceJourney{l:line{c:publicCode m:transportMode}}}";
    // Entur's clock: a trip with identical from/to does no routing and echoes the server time
    const CLOCK = "c:trip(from:{coordinates:{latitude:59.91,longitude:10.75}},to:{coordinates:{latitude:59.91,longitude:10.75}},numTripPatterns:1){dateTime}";

    function body(head, tail, vars, lineIds, withClock) {
        if (lineIds.size() > 0) {
            vars["w"] = { "lines" => lineIds };
        }
        return { "query" => head + (withClock ? CLOCK : "") + tail, "variables" => vars };
    }

    function stopBody(stopId, lineIds, modes, withClock) {
        var vars = { "i" => stopId };
        if (modes.size() > 0) {
            vars["m"] = modes;
        }
        return body("query($i:String!,$w:InputWhiteListed,$m:[TransportMode]){",
            "stopPlace(id:$i){id name estimatedCalls(numberOfDepartures:8,whiteListed:$w,whiteListedModes:$m)" + CALLS + "}}",
            vars, lineIds, withClock);
    }

    function nearestBody(lat, lon, lineIds, withClock) {
        return body("query($a:Float!,$o:Float!,$w:InputWhiteListed){",
            "nearest(latitude:$a,longitude:$o,maximumResults:1,maximumDistance:1000,filterByPlaceTypes:[stopPlace]){edges{node{distance place{... on StopPlace{id name estimatedCalls(numberOfDepartures:8,whiteListed:$w)" + CALLS + "}}}}}}",
            { "a" => lat, "o" => lon }, lineIds, withClock);
    }

    // Public line codes (["17", "31"]) -> Entur line ids
    function linesBody(codes) {
        return { "query" => "query($c:[String]){lines(publicCodes:$c){id}}", "variables" => { "c" => codes } };
    }

    // d[key] when d is a dictionary, else null
    function at(d, key) {
        return (d instanceof Lang.Dictionary) ? d[key] : null;
    }

    // Line ids from a lines reply, or null if it is not one
    function lineIds(root) {
        var lines = at(at(root, "data"), "lines");
        if (!(lines instanceof Lang.Array)) {
            return null;
        }
        var ids = [];
        for (var i = 0; i < lines.size(); i++) {
            var id = at(lines[i], "id");
            if (id instanceof Lang.String) {
                ids.add(id);
            }
        }
        return ids;
    }

    // NSR stop id of the first hit in a geocoder reply, or null
    function geocodedStopId(root) {
        var features = at(root, "features");
        if (features instanceof Lang.Array && features.size() > 0) {
            var id = at(at(features[0], "properties"), "id");
            if (id instanceof Lang.String && id.find("NSR:StopPlace:") == 0) {
                return id;
            }
        }
        return null;
    }

    // Server time (UTC epoch) from the clock field of a reply, or null
    function serverEpoch(root) {
        var dt = at(at(at(root, "data"), "c"), "dateTime");
        return (dt instanceof Lang.String) ? parseIso8601ToEpoch(dt) : null;
    }

    // A countdown is shown only when the server time is known and the departure
    // is within 24 h of it; otherwise the row shows the wall-clock time.
    function isCountdown(item, now) {
        return now != null && (item.expectedEpoch - now).abs() <= 86400;
    }

    // Fills state from a departures reply; false if there is no stop in it.
    // now is server time (UTC epoch), or null when unknown.
    function parse(root, state, now, sortByModeFirst) {
        var data = at(root, "data");
        var place = at(data, "stopPlace");
        var edges = at(at(data, "nearest"), "edges");
        if (edges instanceof Lang.Array && edges.size() > 0) {
            var node = at(edges[0], "node");
            var dist = at(node, "distance");
            state.distanceMeters = (dist == null) ? null : dist.toNumber();
            place = at(node, "place");
        }
        var calls = at(place, "estimatedCalls");
        if (!(calls instanceof Lang.Array) || !(place["id"] instanceof Lang.String) || !(place["name"] instanceof Lang.String)) {
            return false;
        }
        state.stopId = place["id"];
        state.stopName = place["name"];
        state.departures = [];
        for (var i = 0; i < calls.size(); i++) {
            var item = parseCall(calls[i], now);
            // Entur filters by line id; this guards against other lines sharing an id namespace
            if (item != null && DepartureModel.matchesRouteFilter(item.lineCode, state.routeFilter)) {
                state.departures.add(item);
            }
        }
        state.sortDepartures(sortByModeFirst);
        state.status = :ready;
        return true;
    }

    function parseCall(call, now) {
        var iso = at(call, "t");
        var epoch = (iso instanceof Lang.String) ? parseIso8601ToEpoch(iso) : null;
        if (epoch == null) {
            return null;
        }
        var line = at(at(call, "s"), "l");
        var code = at(line, "c");
        var mode = at(line, "m");
        var dest = at(at(call, "d"), "f");
        return new LegacyItem((mode instanceof Lang.String) ? mode : "bus", (code instanceof Lang.String) ? code : "?",
            (dest instanceof Lang.String) ? dest : "", epoch, (now == null) ? epoch : now, call["r"] == true,
            iso.substring(11, 16));
    }

    // "2026-11-01T16:35:00+01:00" or "...Z" -> UTC epoch seconds, by integer
    // arithmetic only: on Connect IQ 1.x Gregorian.moment reads local time.
    function parseIso8601ToEpoch(iso) {
        if (iso.length() < 19) {
            return null;
        }
        var f = [iso.substring(0, 4).toNumber(), iso.substring(5, 7).toNumber(), iso.substring(8, 10).toNumber(),
            iso.substring(11, 13).toNumber(), iso.substring(14, 16).toNumber(), iso.substring(17, 19).toNumber()];
        // 32-bit seconds: stay inside 1970..2037
        if (f.indexOf(null) >= 0 || f[0] < 1970 || f[0] > 2037 || f[1] < 1 || f[1] > 12 || f[2] < 1 || f[2] > 31) {
            return null;
        }
        var epoch = (daysFromCivil(f[0], f[1], f[2]) * 86400) + (f[3] * 3600) + (f[4] * 60) + f[5];

        // Offset "+01:00" / "-05:00" after the seconds and any fraction; "Z" = none
        var rest = iso.substring(19, iso.length());
        var plus = rest.find("+");
        var idx = (plus != null) ? plus : rest.find("-");
        if (idx != null && rest.length() >= idx + 6) {
            var tzHour = rest.substring(idx + 1, idx + 3).toNumber();
            var tzMin = rest.substring(idx + 4, idx + 6).toNumber();
            if (tzHour != null && tzMin != null) {
                epoch = epoch + (((plus != null) ? -1 : 1) * ((tzHour * 3600) + (tzMin * 60)));
            }
        }
        return epoch;
    }

    // Days since 1970-01-01 (Howard Hinnant's days_from_civil)
    function daysFromCivil(y, m, d) {
        if (m <= 2) {
            y = y - 1;
        }
        var era = y / 400;
        var yoe = y - (era * 400);
        var doy = ((153 * (m + ((m > 2) ? -3 : 9))) + 2) / 5 + d - 1;
        return (era * 146097) + (yoe * 365) + (yoe / 4) - (yoe / 100) + doy - 719468;
    }
}

// A departure plus its local wall-clock time ("11:40") as Entur sent it
class LegacyItem extends DepartureModel.DepartureItem {

    var wall;

    function initialize(transportMode, lineCode, destination, expectedEpoch, nowEpoch, isRealtime, wallTime) {
        DepartureItem.initialize(transportMode, lineCode, destination, expectedEpoch, nowEpoch, isRealtime);
        wall = wallTime;
    }
}
