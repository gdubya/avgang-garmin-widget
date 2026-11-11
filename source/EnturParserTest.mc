import Toybox.Lang;
import Toybox.Test;
import DepartureModel;

module EnturParserTest {

    (:test)
    function testParseIso8601Offsets(logger as Test.Logger) as Boolean {
        // "2026-11-01T16:30:00+01:00" == "2026-11-01T15:30:00Z"
        var cetEpoch = EnturApiClient.parseIso8601ToEpoch("2026-11-01T16:30:00+01:00");
        var utcEpoch = EnturApiClient.parseIso8601ToEpoch("2026-11-01T15:30:00Z");
        Test.assert(cetEpoch != null);
        Test.assert(utcEpoch != null);
        Test.assertEqual(cetEpoch, utcEpoch);
        return true;
    }

    (:test)
    function testModeColorsAndLabels(logger as Test.Logger) as Boolean {
        Test.assertEqual("BUS", DepartureModel.DepartureItem.resolveModeLabel("bus"));
        Test.assertEqual("T-B", DepartureModel.DepartureItem.resolveModeLabel("metro"));
        Test.assertEqual("TRK", DepartureModel.DepartureItem.resolveModeLabel("tram"));
        Test.assertEqual("TOG", DepartureModel.DepartureItem.resolveModeLabel("rail"));
        Test.assertEqual("BAT", DepartureModel.DepartureItem.resolveModeLabel("water"));

        Test.assertEqual(0xFF0000, DepartureModel.DepartureItem.resolveModeColor("bus"));
        Test.assertEqual(0xFF5500, DepartureModel.DepartureItem.resolveModeColor("metro"));
        Test.assertEqual(0x00AAFF, DepartureModel.DepartureItem.resolveModeColor("tram"));
        Test.assertEqual(0x00AA00, DepartureModel.DepartureItem.resolveModeColor("rail"));
        Test.assertEqual(0xAA00FF, DepartureModel.DepartureItem.resolveModeColor("water"));
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

        // Chronological only (sortByModeFirst = false)
        state.sortDepartures(false);
        Test.assertEqual("1", state.departures[0].lineCode); // +120s
        Test.assertEqual("37", state.departures[1].lineCode); // +180s
        Test.assertEqual("5", state.departures[2].lineCode); // +300s
        Test.assertEqual("31", state.departures[3].lineCode); // +420s

        return true;
    }

    (:test)
    function testRecalculateCountdownsAndPruning(logger as Test.Logger) as Boolean {
        var state = new DepartureModel.StopBoardState();
        var now = 1793540000;

        var d1 = new DepartureModel.DepartureItem("bus", "31", "Snarøya", now + 300, now, true);
        var d2 = new DepartureModel.DepartureItem("tram", "12", "Majorstuen", now + 20, now, true);

        state.departures = [d1, d2] as Array<DepartureModel.DepartureItem>;
        Test.assertEqual("5m", d1.formatCountdown());
        Test.assertEqual("Now", d2.formatCountdown());

        // Fast forward 80 seconds: d2 is now 60 seconds in the past (> 45s cutoff), so should be pruned
        state.recalculateCountdowns(now + 80);
        Test.assertEqual(1, state.departures.size());
        Test.assertEqual("31", state.departures[0].lineCode);
        Test.assertEqual("3m", state.departures[0].formatCountdown()); // 300 - 80 = 220s = 3m

        return true;
    }

    (:test)
    function testGraphQlPayloadParsing(logger as Test.Logger) as Boolean {
        var state = new DepartureModel.StopBoardState();
        var now = 1793540000;

        // Mock GraphQL response from Entur
        var mockPayload = {
            "data" => {
                "stopPlace" => {
                    "id" => "NSR:StopPlace:58366",
                    "name" => "Jernbanetorget",
                    "estimatedCalls" => [
                        {
                            "realtime" => true,
                            "expectedDepartureTime" => "2026-11-01T20:45:00+01:00",
                            "destinationDisplay" => {
                                "frontText" => "Rikshospitalet"
                            },
                            "serviceJourney" => {
                                "journeyPattern" => {
                                    "line" => {
                                        "publicCode" => "17",
                                        "transportMode" => "tram"
                                    }
                                }
                            }
                        },
                        {
                            "realtime" => false,
                            "expectedDepartureTime" => "2026-11-01T20:48:00+01:00",
                            "destinationDisplay" => {
                                "frontText" => "Grorud T"
                            },
                            "serviceJourney" => {
                                "journeyPattern" => {
                                    "line" => {
                                        "publicCode" => "31",
                                        "transportMode" => "bus"
                                    }
                                }
                            }
                        }
                    ]
                }
            }
        };

        var ok = EnturApiClient.parseGraphQlPayload(mockPayload, state, now, true);
        Test.assert(ok);
        Test.assertEqual("NSR:StopPlace:58366", state.stopId);
        Test.assertEqual("Jernbanetorget", state.stopName);
        Test.assertEqual(2, state.departures.size());

        var tram = state.departures[0];
        Test.assertEqual("17", tram.lineCode);
        Test.assertEqual("TRK", tram.modeLabel);
        Test.assertEqual("Rikshospitalet", tram.destination);
        Test.assert(tram.isRealtime);

        var bus = state.departures[1];
        Test.assertEqual("31", bus.lineCode);
        Test.assertEqual("BUS", bus.modeLabel);
        Test.assertEqual("Grorud T", bus.destination);
        Test.assert(!bus.isRealtime);

        return true;
    }

    (:test)
    function testChordHalfWidth(logger as Test.Logger) as Boolean {
        // At vertical equator on 454x454 with 11px margin: effective radius is 216
        var eqHalf = RuterWidgetView.computeChordHalfWidth(210, 244, 454, 454, 11);
        Test.assert(eqHalf >= 214 && eqHalf <= 216);

        // Near top on 454x454 (y=27..64): chord width must be strictly narrower than equator
        var topHalf = RuterWidgetView.computeChordHalfWidth(31, 64, 454, 454, 11);
        Test.assert(topHalf > 75 && topHalf < 100);

        // Outside effective circle returns 0
        var outHalf = RuterWidgetView.computeChordHalfWidth(0, 5, 454, 454, 11);
        Test.assertEqual(0, outHalf);

        // 240x240 row band (y=60..190) stays safely inside bezel
        var f6Half = RuterWidgetView.computeChordHalfWidth(60, 190, 240, 240, 6);
        Test.assert(f6Half > 85 && f6Half < 105);

        return true;
    }
}
