# Privacy Policy

**Last Updated:** November 1, 2026

This Privacy Policy describes how the **Avgang - Live Transit Norway** widget ("the Widget") handles your data. We believe in complete privacy: the Widget has no third-party tracking, no developer backends, and collects zero personal data.

---

## 1. Information Handled by the Widget

### Location Data (GPS)
* **How it is used:** When the active stop mode is set to **`GPS Nearest Stop`**, the Widget accesses on-device GPS coordinates (latitude and longitude) provided by the watch's built-in positioning system.
* **Destination:** Coordinates are sent directly and securely over HTTPS to **Entur AS** (`https://api.entur.io`) to discover the nearest public transport stop.
* **Storage:** GPS coordinates are never retained, logged, or stored by the Widget once the API request completes.

### User Settings and Favorite Stops
* **How it is used:** Favorite stop queries (`stopQuery1`, `stopQuery2`, `stopQuery3`) and pinned stop IDs are saved locally on the watch using Garmin's encrypted on-device storage (`Toybox.Application.Storage` and `Toybox.Application.Properties`).
* **Destination:** Stop queries and IDs are sent solely to Entur's open JourneyPlanner and Geocoder APIs to retrieve schedule information.
* **Storage:** No settings or queries are ever uploaded to any developer server.

### No Personal Data or Analytics Collected
The Widget **does not** collect, store, or share:
* Your name, email, or Garmin account credentials.
* Device serial numbers, IP addresses, or unique hardware identifiers.
* Fitness, health, biometric, or sensor data.
* Usage analytics, crash logs, or telemetry.

---

## 2. Third-Party Services (Entur AS)

Public transport schedule data, live departures, and geocoding services are retrieved directly from **Entur AS** (Norway's national public transport platform) under the *Norwegian License for Open Government Data (NLOD)*.

* Communication occurs directly between your watch (bridged through your paired mobile device running Garmin Connect) and Entur's endpoints (`api.entur.io`).
* Like any web service, Entur receives standard network protocol metadata (such as client IP address and HTTP headers) when fulfilling requests. For more details, consult [Entur's Privacy Statement](https://entur.no/om-entur/personvern).

---

## 3. Open Source Transparency

This Widget is an open-source project. Its complete source code is publicly accessible and auditable on GitHub at [github.com/gdubya/avgang-garmin-widget](https://github.com/gdubya/avgang-garmin-widget).

---

## 4. Changes to This Policy

If changes are made to this Privacy Policy, the updated document will be published with an updated revision date in this repository.

---

## 5. Contact

If you have questions or concerns regarding this Privacy Policy, please open an issue in the [GitHub issue tracker](https://github.com/gdubya/avgang-garmin-widget/issues).
