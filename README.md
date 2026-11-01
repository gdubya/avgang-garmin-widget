# Ruter / Entur Garmin Widget (`ruter-garmin-widget`)

A lightweight Garmin Connect IQ widget for the **Garmin fēnix 6S** (and fēnix 6S Pro) that displays real-time countdowns for upcoming public transit departures in Norway using the open **Entur JourneyPlanner v3 GraphQL API** (which powers Ruter and all Norwegian public transit operators).

## Features (Option A - Direct Watch-to-Entur)

- **Zero Backend Required**: Queries `https://api.entur.io/journey-planner/v3/graphql` directly over BLE via Garmin Connect Mobile.
- **Memory-Optimized for fēnix 6S**: Requests a minimal GraphQL selection set so the parsed JSON dictionary stays well within the 64 KB widget memory budget.
- **Glance & Full-Screen Widget Views**:
  - **Glance View**: Quick one-line summary of the very next departure when scrolling the widget carousel.
  - **Full-Screen View**: Shows the stop name and the next 3 upcoming departures (line code, destination, and minutes remaining), with manual refresh and mode toggle via watch buttons.
- **Configured Stop + Optional GPS Nearest Stop**:
  - Configure a default favorite `NSR:StopPlace` ID in Garmin Connect App Settings for instant indoor lookups.
  - Optionally fall back to or trigger a GPS lookup using Entur's `nearest` GraphQL query.

## Project Structure

```text
ruter-garmin-widget/
├── manifest.xml                  # Connect IQ app metadata, target devices & permissions
├── monkey.jungle                 # Monkey C build configuration
├── resources/
│   ├── drawables/                # App icon and drawable definitions
│   ├── properties/               # Configurable settings (StopPlace ID, max departures, GPS toggle)
│   └── strings/                  # Localized UI & settings strings
└── source/
    ├── RuterWidgetApp.mc         # Application entry point & lifecycle
    ├── EnturApiClient.mc         # Direct GraphQL client & ISO-8601 countdown parser
    ├── DepartureModel.mc         # Compact data structures for stop & departure entries
    ├── RuterGlanceView.mc        # (:glance) Carousel glance view
    ├── RuterWidgetView.mc        # Full-screen 240x240 circular departure board
    └── RuterWidgetDelegate.mc    # Button input handler (Select = Refresh, Menu = Toggle GPS/Fixed)
```
