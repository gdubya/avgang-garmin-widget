using Toybox.Test as Test;

// Tests for source-legacy/LegacyParse.mc (Connect IQ 1.x watches). Toybox.Test
// is API 2.1, so they run on a modern device profile, see legacy-test.jungle.
module LegacyParseTest {

    // ISO -> epoch is pure arithmetic, independent of the device clock and time
    // zone. Expected values computed with Python's datetime.
    (:test)
    function testIsoToEpoch(logger) {
        Test.assertEqual(1794825541, LegacyParse.parseIso8601ToEpoch("2026-11-16T11:39:01+01:00")); // winter
        Test.assertEqual(1782811800, LegacyParse.parseIso8601ToEpoch("2026-06-30T11:30:00+02:00")); // summer
        Test.assertEqual(1782811800, LegacyParse.parseIso8601ToEpoch("2026-06-30T09:30:00Z"));
        Test.assertEqual(1794825541, LegacyParse.parseIso8601ToEpoch("2026-11-16T05:39:01-05:00"));
        Test.assertEqual(1794825541, LegacyParse.parseIso8601ToEpoch("2026-11-16T11:39:01.250+01:00"));
        // 00:30 local on 1 Jan is still 31 Dec in UTC
        Test.assertEqual(1798759800, LegacyParse.parseIso8601ToEpoch("2027-01-01T00:30:00+01:00"));
        // leap day 2028 and the days around it
        Test.assertEqual(1835348400, LegacyParse.parseIso8601ToEpoch("2028-02-28T12:00:00+01:00"));
        Test.assertEqual(1835434800, LegacyParse.parseIso8601ToEpoch("2028-02-29T12:00:00+01:00"));
        Test.assertEqual(1835521200, LegacyParse.parseIso8601ToEpoch("2028-03-01T12:00:00+01:00"));
        Test.assertEqual(0, LegacyParse.parseIso8601ToEpoch("1970-01-01T00:00:00Z"));
        // malformed or out of range -> null, never a bogus number
        Test.assert(LegacyParse.parseIso8601ToEpoch("garbage") == null);
        Test.assert(LegacyParse.parseIso8601ToEpoch("2026-xx-16T11:39:01Z") == null);
        Test.assert(LegacyParse.parseIso8601ToEpoch("2026-13-01T00:00:00Z") == null);
        Test.assert(LegacyParse.parseIso8601ToEpoch("2040-01-01T00:00:00Z") == null);
        return true;
    }

    function payload() {
        return { "data" => {
            "c" => { "dateTime" => "2026-11-01T20:40:00+01:00" },
            "stopPlace" => { "id" => "NSR:StopPlace:6059", "name" => "Valle", "estimatedCalls" => [
                { "r" => true, "t" => "2026-11-01T20:48:00+01:00", "d" => { "f" => "Helsfyr" },
                  "s" => { "l" => { "c" => "21", "m" => "bus" } } },
                { "r" => false, "t" => "2026-11-01T20:45:00+01:00", "d" => { "f" => "Kolsås" },
                  "s" => { "l" => { "c" => "3", "m" => "metro" } } }
            ] }
        } };
    }

    (:test)
    function testParseBoard(logger) {
        var state = new DepartureModel.StopBoardState();
        var now = LegacyParse.serverEpoch(payload());
        Test.assertEqual(LegacyParse.parseIso8601ToEpoch("2026-11-01T19:40:00Z"), now);
        Test.assert(LegacyParse.parse(payload(), state, now, false));
        Test.assertEqual("NSR:StopPlace:6059", state.stopId);
        Test.assertEqual("Valle", state.stopName);
        Test.assertEqual(2, state.departures.size());
        // time-sorted: metro 3 (20:45) before bus 21 (20:48)
        Test.assertEqual("3", state.departures[0].lineCode);
        Test.assertEqual("metro", state.departures[0].transportMode);
        Test.assertEqual("Kolsås", state.departures[0].destination);
        Test.assert(!state.departures[0].isRealtime);
        Test.assertEqual("5m", state.departures[0].formatCountdown());
        Test.assert(state.departures[1].isRealtime);

        // the client-side guard keeps only the filtered lines
        state.routeFilter = ["21"];
        Test.assert(LegacyParse.parse(payload(), state, now, true));
        Test.assertEqual(1, state.departures.size());
        Test.assertEqual("21", state.departures[0].lineCode);

        // GPS nearest reply, and replies without a stop
        Test.assert(LegacyParse.parse({ "data" => { "nearest" => { "edges" => [ { "node" => { "distance" => 53.4,
            "place" => { "id" => "NSR:StopPlace:6059", "name" => "Valle", "estimatedCalls" => [] } } } ] } } }, state, now, true));
        Test.assertEqual(53, state.distanceMeters);
        Test.assertEqual(0, state.departures.size());
        Test.assert(!LegacyParse.parse({ "errors" => [] }, state, now, true));
        Test.assert(!LegacyParse.parse({ "data" => { "stopPlace" => null } }, state, now, true));
        Test.assert(!LegacyParse.parse({ "data" => { "nearest" => { "edges" => [] } } }, state, now, true));
        return true;
    }

    // Without a sane server clock a row shows Entur's wall-clock time, never "1283325m"
    (:test)
    function testClockFallback(logger) {
        Test.assert(LegacyParse.serverEpoch({ "data" => { "c" => null } }) == null);
        Test.assert(LegacyParse.serverEpoch({ "data" => { "c" => { "dateTime" => 1794825541 } } }) == null);

        var state = new DepartureModel.StopBoardState();
        Test.assert(LegacyParse.parse(payload(), state, null, false));
        var item = state.departures[0] as LegacyItem;
        Test.assertEqual("20:45", item.wall);
        Test.assert(!LegacyParse.isCountdown(item, null));
        var now = LegacyParse.serverEpoch(payload());
        Test.assert(LegacyParse.isCountdown(item, now));
        Test.assert(LegacyParse.isCountdown(item, now - 86000));
        Test.assert(!LegacyParse.isCountdown(item, now - (891 * 86400)));
        Test.assert(!LegacyParse.isCountdown(item, now + (3 * 86400)));
        return true;
    }

    (:test)
    function testRequests(logger) {
        // no double quotes in any query text (the simulator does not escape them)
        Test.assert(LegacyParse.stopBody("x", [], [], true)["query"].find("\"") == null);
        Test.assert(LegacyParse.nearestBody(59.9, 10.8, [], true)["query"].find("\"") == null);
        Test.assert(LegacyParse.linesBody(["21"])["query"].find("\"") == null);
        // the clock field is only there when asked for
        Test.assert(LegacyParse.stopBody("x", [], [], true)["query"].find("c:trip(") != null);
        Test.assert(LegacyParse.stopBody("x", [], [], false)["query"].find("c:trip(") == null);
        Test.assert(LegacyParse.nearestBody(59.9, 10.8, [], true)["query"].find("c:trip(") != null);

        // filters are variables, and absent when empty
        var vars = LegacyParse.stopBody("NSR:StopPlace:59516", [], [], false)["variables"];
        Test.assertEqual("NSR:StopPlace:59516", vars["i"]);
        Test.assert(vars["w"] == null);
        Test.assert(vars["m"] == null);
        vars = LegacyParse.stopBody("NSR:StopPlace:59516", ["RUT:Line:21"], ["bus"], false)["variables"];
        Test.assertEqual("RUT:Line:21", vars["w"]["lines"][0]);
        Test.assertEqual("bus", vars["m"][0]);
        // the mode filter never goes to GPS nearest
        Test.assert(LegacyParse.nearestBody(59.9, 10.8, ["RUT:Line:21"], false)["query"].find("whiteListedModes") == null);
        Test.assertEqual("RUT:Line:21", LegacyParse.nearestBody(59.9, 10.8, ["RUT:Line:21"], false)["variables"]["w"]["lines"][0]);
        Test.assertEqual("31", LegacyParse.linesBody(["17", "31"])["variables"]["c"][1]);
        return true;
    }

    (:test)
    function testLookupReplies(logger) {
        var ids = LegacyParse.lineIds({ "data" => { "lines" => [ { "id" => "RUT:Line:17" }, "junk", { "id" => "MOR:Line:17" } ] } });
        Test.assertEqual(2, ids.size());
        Test.assertEqual("MOR:Line:17", ids[1]);
        // no such line is an empty list; anything else is not a lines reply
        Test.assertEqual(0, LegacyParse.lineIds({ "data" => { "lines" => [] } }).size());
        Test.assert(LegacyParse.lineIds({ "errors" => [] }) == null);

        Test.assertEqual("NSR:StopPlace:58366", LegacyParse.geocodedStopId({ "features" => [
            { "properties" => { "id" => "NSR:StopPlace:58366", "name" => "Jernbanetorget" } } ] }));
        Test.assert(LegacyParse.geocodedStopId({ "features" => [] }) == null);
        // a place that is not a stop
        Test.assert(LegacyParse.geocodedStopId({ "features" => [ { "properties" => { "id" => "KVE:TopographicPlace:0301" } } ] }) == null);
        return true;
    }
}
