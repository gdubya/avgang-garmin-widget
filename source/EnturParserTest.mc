import Toybox.Lang;
import Toybox.Test;
import DepartureModel;

module EnturParserTest {

    (:test)
    function testParseIso8601Offsets(logger as Test.Logger) as Boolean {
        // "2026-11-01T16:30:00+01:00" == "2026-11-01T15:30:00Z"
        var cetEpoch = EnturApiClient.parseIso8601ToEpoch("2026-11-01T16:30:00+01:00");
        var utcEpoch = EnturApiClient.parseIso8601ToEpoch("2026-11-01T15:30:00Z");
        Test.assertNotNull(cetEpoch);
        Test.assertNotNull(utcEpoch);
        Test.assertEqual(cetEpoch, utcEpoch);
        return true;
    }

    (:test)
    function testSortByModeAndTime(logger as Test.Logger) as Boolean {
        var state = new DepartureModel.StopBoardState();
        var now = 1793540000;

        // Earliest overall is a metro (at +120s), then a bus (at +180s), then another metro (at +300s), then another bus (at +420s)
        var d1 = new DepartureModel.DepartureItem("bus", "31", "Snarøya", now + 420, now, true);
        var d2 = new DepartureModel.DepartureItem("metro", "5", "Sognsvann", now + 300, now, true);
        var d3 = new DepartureModel.DepartureItem("bus", "37", "Nydalen", now + 180, now, true);
        var d4 = new DepartureModel.DepartureItem("metro", "1", "Frognerseteren", now + 120, now, true);

        state.departures = [d1, d2, d3, d4] as Array<DepartureModel.DepartureItem>;
        state.sortDepartures(true);

        // Mode with earliest departure ("metro" at +120s) should come first, sorted by time:
        // [0] metro 1 (+120s), [1] metro 5 (+300s), [2] bus 37 (+180s), [3] bus 31 (+420s)
        Test.assertEqual("metro", state.departures[0].transportMode);
        Test.assertEqual("1", state.departures[0].lineCode);
        Test.assertEqual("metro", state.departures[1].transportMode);
        Test.assertEqual("5", state.departures[1].lineCode);
        Test.assertEqual("bus", state.departures[2].transportMode);
        Test.assertEqual("37", state.departures[2].lineCode);
        Test.assertEqual("bus", state.departures[3].transportMode);
        Test.assertEqual("31", state.departures[3].lineCode);

        return true;
    }
}
