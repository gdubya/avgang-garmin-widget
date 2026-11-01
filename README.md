# Ruter / Entur Garmin Widget (`ruter-garmin-widget`)

A native Garmin Connect IQ widget displaying real-time public transport countdowns in Norway directly from the **Entur JourneyPlanner v3 GraphQL API** and **Entur Geocoder API**.

> **Device Compatibility Note:** This widget was **developed primarily and optimized for the Garmin fēnix 6S** (`fenix6s` / `fenix6spro`). It is also built and packaged for other circular Garmin watches with identical or similar screen layouts (fēnix 6/7 series, Epix 2, Forerunner 255/265/955/965, and Enduro), but UI elements and font sizing were tuned specifically for the fēnix 6S display.

---

## Features (Option A — Direct Watch-to-Entur)

1. **Zero Backend Required**:
   - Communicates directly with `https://api.entur.io/journey-planner/v3/graphql` and `https://api.entur.io/geocoder/v1/autocomplete` over Bluetooth via Garmin Connect Mobile.
   - Compact GraphQL query (~850 bytes response for 8 departures) engineered to stay safely inside the fēnix 6S 64 KB widget / 32 KB glance memory limits.
2. **Mobile + On-Watch Stop Configuration**:
   - **Garmin Connect Mobile App Settings**: Configure up to 3 favorite stops (`stopQuery1`, `stopQuery2`, `stopQuery3`) using **either a human-readable stop name** (e.g. `"Jernbanetorget"`, `"Majorstuen"`, `"Nationaltheatret"`) **or an explicit ID** (`"NSR:StopPlace:59872"`). Stop names are resolved automatically via Entur's Geocoder API and cached in on-watch storage.
   - **On-Watch `Menu2` Settings (Hold UP/MENU)**:
     - **Stop Source**: Switch between `GPS Nearest Stop`, `Favorite 1..3`, or `Pinned Watch Stop`.
     - **Pin Current Stop**: Save a stop discovered via GPS directly to the watch for instant indoor use.
     - **Sort Order**: Toggle between `Mode + Time` and `Time Only`.
3. **Multi-Modal Sorting & Color Badges**:
   - Supports all Norwegian transit modes: **Bus (`BUS`)**, **T-bane (`T-B`)**, **Tram (`TRK`)**, **Train (`TOG`)**, and **Ferry (`BAT`)**.
   - Groups departures by transport mode (ordered by whichever mode has the soonest departure first) and sorts chronologically within each mode.

---

## fēnix 6S Button Controls

| Watch Button | Action |
| :--- | :--- |
| **START / STOP** (Top-Right) | Immediately refresh live departures from Entur |
| **DOWN** (Bottom-Left) | Scroll down through upcoming departures |
| **UP** (Middle-Left) | Scroll up through upcoming departures |
| **Hold UP / MENU** (Middle-Left) | Open on-watch `Ruter Config` menu (Stop Source, Pin Stop, Sort Order) |

---

## On-Watch Configuration & Stop Sources

Hold the **UP / MENU** button inside the widget to open the **Ruter Config** menu.

### 1. Stop Source

Pressing **Stop Source** cycles through 5 transit sources:

| Source | Description | Typical Use Case |
| :--- | :--- | :--- |
| **`GPS Nearest Stop`** | Uses watch GPS coordinates to find the nearest bus, tram, metro, train, or ferry stop. | Exploring unfamiliar areas or traveling around town. |
| **`Fav 1`** *(Default: Jernbanetorget)* | Loads your 1st preset stop configured in phone settings. | Primary morning commute station (e.g. home station). |
| **`Fav 2`** *(Default: Majorstuen)* | Loads your 2nd preset stop configured in phone settings. | Work, school, or study hub. |
| **`Fav 3`** *(Default: Nationaltheatret)* | Loads your 3rd preset stop configured in phone settings. | Gym, evening meetup, or weekend spot. |
| **`Pinned Stop`** | Loads the stop saved directly on the watch via **Pin Current Stop**. | Instant indoor access without GPS lock or phone setup. |

> **Tip:** You can customize the stop names or IDs for Favorites 1–3 anytime in the **Garmin Connect Mobile app** under *App Settings*.

### 2. How to Use "Pin Current Stop"

#### The Problem it Solves:
GPS cannot reliably acquire satellite lock indoors (e.g. inside your apartment, hallway, or office before heading out), and typing a new stop name in the mobile app settings is tedious when you are on the go.

#### Step-by-Step Walkthrough:
1. When you are outdoors near a transit stop you frequently use, cycle **Stop Source** to **`GPS Nearest Stop`** and wait for the departures to load.
2. Hold **UP / MENU** to open the config menu.
3. Select **Pin Current Stop** (press **START**).
4. The menu updates to display `Saved: <Stop Name>` and automatically switches your active source to **Pinned**.
5. **From now on**, whenever you check the widget before stepping out the door, it will instantly fetch live countdowns for that exact stop with **zero GPS wait** and **no phone configuration required**.

### 3. Sort Order
Toggles between:
* **`Mode + Time` (Default)**: Groups departures by transit mode (prioritizing whichever mode has the earliest departure) and sorts chronologically within each mode.
* **`Time Only`**: Pure chronological order across all modes.

---

## Project Structure

```text
ruter-garmin-widget/
├── manifest.xml                  # Connect IQ app metadata, target devices & permissions
├── monkey.jungle                 # Monkey C build configuration
├── resources/
│   ├── drawables/                # 40x40 LauncherIcon bitmap
│   ├── properties/               # Mobile App Settings & Properties (activeStopMode, stopQuery1..3, sortByModeFirst)
│   └── strings/                  # UI & Settings strings
└── source/
    ├── RuterWidgetApp.mc         # (:glance) Application entry point & settings listener
    ├── DepartureModel.mc         # (:glance) Data models & Mode+Time sorting algorithm
    ├── EnturApiClient.mc         # (:glance) Entur GraphQL + Geocoder client & ISO-8601 parser
    ├── RuterGlanceView.mc        # (:glance) Widget carousel glance view
    ├── RuterWidgetView.mc        # 240x240 circular multi-modal departure board
    ├── RuterWidgetDelegate.mc    # Button handling & on-watch Menu2 configuration delegate
    └── EnturParserTest.mc        # (:test) Unit tests for ISO-8601 parsing & Mode+Time sorting
```

---

## Building & Running in the Connect IQ Simulator

1. Install the **Garmin Connect IQ SDK Manager** and the **Monkey C** VS Code extension.
2. Download the **fēnix 6S** (`fenix6s` / `fenix6spro`) device definitions in the SDK Manager.
3. Generate a developer key if you don't already have one:
   ```bash
   openssl genrsa -out developer_key.pem 4096
   openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
   ```
4. Compile for `fenix6s`:
   ```bash
   monkeyc -f monkey.jungle -d fenix6s -o bin/RuterWidget.prg -y developer_key.der -w
   ```
5. Run unit tests in the simulator:
   ```bash
   monkeyc -f monkey.jungle -d fenix6s -o bin/RuterWidgetTest.prg -y developer_key.der -t
   # Note: on Windows monkeydo requires /t (forward slash)
   monkeydo bin/RuterWidgetTest.prg fenix6s /t
   ```
6. Side-load onto your physical fēnix 6S:
   - Connect your fēnix 6S via USB and copy `bin/RuterWidget.prg` into `GARMIN/APPS/` on the watch drive.

---

## Privacy Policy

This widget respects your privacy: zero trackers, zero developer backends, and no personal data collection. Read the full [Privacy Policy](PRIVACY.md).
