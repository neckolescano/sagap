# Sagap — MVP Spec

Version 0.1 · 2026-11-19 · Status: draft for review · SPEC.md is the source of truth.

**Tags used below**
- **[D]** decided in the brief or `app-ideas-notes.md` (not reopened)
- **[V]** verified in official Android / ARCore / Flutter docs during this spec run (link in §16)
- **[J]** my judgment or proposal; change it freely
- **[?]** not supported by the inputs; verify on a real phone or decide

---

## 1. Product in one paragraph

Sagap maps a home's Wi-Fi from one walk-through. ARCore tracks the phone's position in meters while the app logs the connected network's signal about once per second [D]. The result is a floor sketch plus a heatmap. The app then gives cost-ranked fixes: free (move router, channel, band, antennas) → cheap extender → mesh [D]. Sagap **measures and advises; it never claims to boost Wi-Fi**. Android only, fully offline, no accounts, no ads, no cloud [D].

**Out of MVP:** iOS, accounts, sync, ads, floor-plan upload [D]. Before/after proof, shareable Taglish report, step-counter fallback, Gaussian-process heatmap, multi-floor [J: Later; see §15].

## 2. Architecture and key technical choices

| Choice | Decision | Why (one line) |
|---|---|---|
| State management | **Riverpod** (`flutter_riverpod` ^3.5.0) — approved 2026-11-19 | Native streams map to `StreamProvider`; logic is testable without widgets; fakes swap in via overrides. |
| Storage | **SQLite** (`sqflite` ^2.4.6) — approved 2026-11-19 | Data is relational (home → scan → samples) and the heatmap queries by scan; Hive is key-value. |
| Navigation | Built-in `Navigator` + Material 3 `NavigationBar` [J] | 3 tabs need no routing package. |
| Native bridge | `MethodChannel` for commands [V]; `EventChannel` for RSSI and pose streams [J, ?: EventChannel was not on the fetched page; confirm in the Flutter API reference] | Commands vs. continuous data. |
| Channel threads | Handlers run on the Android main thread by default [V] | Keep Kotlin handlers short; heavy work stays off the main thread. |
| AR view | ARCore `GLSurfaceView` in an `AndroidView` with **Hybrid Composition** [J] | Hybrid Composition has correct SurfaceView support [V]. Known cost: it "degrades Flutter FPS" [V]. Fallback: a native Kotlin Activity for the live AR scan (decide in M2). |
| AR install mode | **AR Optional** manifest [V] | AR Required would hide the app from unsupported phones on Play Store, killing the fallback [V]. minSdk 24 [V]. |
| Heavy math | IDW and model fitting in a Dart isolate (`compute`) [J] | Keeps the map responsive. |
| Sample pairing | In Dart (pure function), not Kotlin [J] | Easy to unit-test with fixed inputs. |

**Folders [J]:** `lib/core` (theme, constants, signal words) · `lib/platform` (channel wrappers + fakes) · `lib/data` (DB, repositories) · `lib/domain` (pure Dart: IDW, path-loss fit, extender, hotspot compare, ranking) · `lib/features/{onboarding,scan,map,homes}` · `android/.../{WifiReader, ArSessionManager, ArPlatformView}.kt`.

**Proposed channels [J]:** `sagap/wifi` (method: `startRssi`, `stopRssi`, `requestChannelScan`, `scanBudget`) · `sagap/rssi` (event) · `sagap/ar` (method: `checkAvailability`, `requestInstall`, `start`, `pause`, `stop`, `hitTestCorner`, `markCornerHere`) · `sagap/pose` (event).

## 3. Signal in words

Every value is shown as a word first; dBm is secondary text [D]. Thresholds are **[?] not given by the inputs**; the only anchor is that −60 to −65 dBm is "still good" [D]. Proposed named constants:

| Word | RSSI (dBm) | Heatmap colour | Legend pattern |
|---|---|---|---|
| Excellent | ≥ −59 | green | solid |
| Good | −60 … −69 | yellow-green | dots |
| Weak | −70 … −79 | yellow/orange | diagonal lines |
| Dead zone | ≤ −80 | red | cross-hatch |

Alternative: Android's `WifiManager.calculateSignalLevel` [V: WifiInfo docs point to it]. It needs a mapping from levels to the 4 words.

## 4. Screens and navigation

Bottom tabs: **Scan · Map · Homes** [D]. The first launch shows the guide, then lands on Scan.

| # | Screen | Purpose | Main components | Navigation |
|---|---|---|---|---|
| S1 | First-run guide | Teach the walk in 3 illustrated steps [D] | ① "Stand next to your router, press Start" ② "Walk every room at chest height; tap room corners" ③ "Get your fixes" · Skip · Next | App first launch → S2 → Scan tab. Re-open from S13. |
| S2 | Permission explainer | Explain why, just before asking (§6) | Plain-language reason, Allow / Not now | Shown just-in-time from S3/S4 |
| S3 | Scan – ready | Pick home, check readiness | Home picker / "New home", mode badge (AR or Manual), connection word, **Start** (bottom, large) | Scan tab root → S4 or S5 |
| S4 | Scan – live (AR) | Record the walk | Camera view, **big live signal meter** (word + small dBm), **mini-map** of walked path coloured by signal, tracking banner, Mark corner, Add priority spot, **Pause / Finish** in thumb zone [D] | S3 → S7. On AR loss → offer S5 |
| S5 | Scan – live (Manual) | Fallback recording | Room sketch canvas, "I'm here — Record" (5 s average), big meter, Pause / Finish | S3 or S6 → S7 |
| S6 | Room sketch editor | Hand-drawn rooms [D] | Add rectangle, name, width × length (m), drag/snap, mark router, priority spots | S3 (manual) → S5 |
| S7 | Scan summary | Confirm and save | Area covered, samples, dead zones found, channel check result, loop-closure quality, Save / Discard | S4/S5 → Map tab (S8) |
| S8 | Map | Heatmap of a scan | Heatmap (measured **solid**, predicted **hatched + faded** [D]), legend with words + patterns, layer toggles (path, walls, spots), tap cell → "Weak · −74 dBm · measured", **Fixes**, **What if** | Map tab root → S9, S10, S11 |
| S9 | Fixes | Recommendations | Cards ranked by cost (§9): what · where (map pin) · expected improvement + evidence tag | S8 → card tap → S8 with pin |
| S10 | What-if simulator | Preview a router move | Draggable router, predicted heatmap (all hatched), before/after numbers, model-quality badge | S8. Disabled with a reason if the model fails its check |
| S11 | Hotspot test | Compare 2–3 router spots with laptop hotspot [D] | Setup candidates → per-candidate checklist of priority spots → results | S8 or S9 → results card in S9 |
| S12 | Homes | Manage saved homes | Home list, scan count, last scan date, rename, delete | Homes tab root → S13 |
| S13 | Home detail / Settings | Scans and app settings | Scan list (open in Map, delete), theme (Dark default / Light / System), privacy note, delete all data, replay guide | S12 |

## 5. Data model (SQLite) [J]

| Table | Key columns |
|---|---|
| `homes` | id, name, created_at |
| `scans` | id, home_id, started_at, ended_at, mode (`ar`/`manual`), purpose (`survey`/`hotspot`), candidate_label, router_x, router_y, loop_error_m |
| `samples` | id, scan_id, t_ms (monotonic), x_m, y_m, rssi_dbm, freq_mhz, ap_index, position_source (`ar`/`manual`), tracking_ok |

**Implemented in M3 (schema v2, 2026-11-20).** The tables are built as each milestone needs them:
- `scans`: id, home_id, started_at, duration_ms, mode (`ar` / `signal`), sample_count, median_dbm, walked_m, loop_error_m. `signal` = no positions (no AR, or camera denied); `manual` arrives in M6. Router, purpose and candidate columns come with M4/M9.
- `samples`: id, scan_id, t_ms, rssi_dbm, freq_mhz, x_m, y_m. x/y are null for `signal` scans. AR readings with no tracked pose within 300 ms are not stored (AT6). `ap_index` comes with the channel check (M7).
- `path_points`: scan_id, segment, seq, x_m, y_m (the filtered path from the mini-map).
- Deletes are explicit transactions, not foreign-key cascades.
- v1 → v2 migration keeps `app_settings`.
- v3 (M6): `rooms` (home_id, name, x, y, w, h), `priority_spots` (home_id, label, x, y), and `homes.router_x/y`. The router lives on the home's sketch, not on each scan. Scan mode `manual` added.
- v4 (M7): `channel_checks` (scan_id, json). The JSON holds only the own frequency, whether results were fresh, and the strong-neighbour count per frequency.
- v5 (M9): `hotspot_tests` (home_id, started_at, json: candidate labels and points, plus per-spot medians). Stored per home rather than as a scan with `purpose = hotspot`, since a test has no walk.
| `path_points` | scan_id, t_ms, x_m, y_m (mini-map; 2 Hz) |
| `walls` | id, home_id, x1, y1, x2, y2, source (`traced`/`sketch`) |
| `rooms` | id, home_id, name, x, y, w, h (manual mode) |
| `priority_spots` | id, home_id, label, x, y |
| `channel_checks` | id, scan_id, t, own_freq_mhz, per-channel counts of strong neighbours (aggregates only) |

**Privacy rules:**
- No SSID or BSSID is stored or logged.
- `ap_index` is a per-scan counter (1, 2, …). It is assigned in memory when the connected access point changes, so roaming to an extender shows up without storing identifiers.
- Recommendations are computed on demand, not stored.
- Positions are local meters in AR space, not GPS.

## 6. Android permissions

| Permission | Type / when requested | Used for | If denied |
|---|---|---|---|
| `CAMERA` | Runtime; on first **Start** in AR mode (S2) | ARCore session. Must be granted before session creation [V] | Manual mode (S5/S6) with a one-line reason; retry via Settings link |
| `ACCESS_FINE_LOCATION` (+ `ACCESS_COARSE_LOCATION` declared [?: Android 12 pairing rule, not fetched]) | Runtime; on first **Start**, after camera | `startScan`/`getScanResults` need it on Android 10+, also on 13+ [V]; needed to see BSSID for `ap_index` [V: SSID/BSSID are location-sensitive] | Live map still runs: RSSI was read with no location permission on an itel S665L, Android 12 (2026-11-20, phone test). Other phones/versions not yet tested. Channel check and `ap_index` disabled; the "change channel" card is replaced by a manual tip. |
| Location services (system toggle) | Checked before a channel scan | Required for scans on Android 9+ [V] | Skip channel check; banner "Turn on Location to check Wi-Fi channels" |
| `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE` | Install-time (normal) [?: protection level not fetched] | Read Wi-Fi info; start scans [V] | n/a |
| `ACCESS_NETWORK_STATE` | Install-time (normal) [?] | `ConnectivityManager` network callback | n/a |
| `NEARBY_WIFI_DEVICES` | **Not declared** [J]. Fine location is requested once per app launch, at Start, with a reason dialog (built in M7). | The docs still require FINE_LOCATION for scan APIs on 13+ [V] | n/a |
| `INTERNET` | **Not declared in release** [J] | Offline guarantee | Check the merged manifest in M0/M2. If a library adds it, document why. |

## 7. Sampling: signal + position

**RSSI (live map)**
- Source: `WifiInfo.getRssi()` from `ConnectivityManager` `NetworkCallback.onCapabilitiesChanged` → `getTransportInfo()`. `getConnectionInfo` is deprecated since API 31 [V].
- Rate: read about once per second [D]. Kotlin emits `{t, rssi, freqMHz, apChanged}` via `sagap/rssi` at 1 Hz from the latest `WifiInfo`.
- [?] Whether the callback fires on each RSSI change is not in the docs. Fallback: poll the deprecated `getConnectionInfo` (still callable) and measure the real rate in M1.
- [?] The "unavailable" RSSI value is not documented. Treat values outside −100…0 dBm as invalid (named constants) and drop them.

**Full scans (channel check only) [D]**
- Throttling: 4 scans per 2 minutes per foreground app on Android 9+ [V].
- The app keeps its own budget counter and uses at most 2 scans per survey: at Start and at Finish [J]. Results are reduced to per-channel counts of neighbours stronger than −70 dBm [J].
- `startScan` may be deprecated (API 28) [?: from a doc summary, not verbatim]; it is still used.
- The developer-option throttle toggle is for local testing only [V].

**Position (AR)**
- ARCore camera pose; translation is in meters [V].
- Floor plane = world X–Z, assuming gravity-aligned Y-up [?: confirm in M2].
- Pose is emitted at 5 Hz via `sagap/pose` with tracking state and `TrackingFailureReason` [J].
- Both streams carry monotonic timestamps. Dart pairs each RSSI reading with the nearest pose within 300 ms [J]. No pose or not TRACKING → no sample (`tracking_ok = false` is kept only for the path).

**Walls (AR)**
- "Tap corners to trace walls" [D]: a tap hit-tests the detected floor plane at the wall–floor corner.
- Fallback when no plane is found: "Mark corner here" uses the phone's current position while standing in the corner [J].
- Consecutive corners form wall segments; the user can close a room.

**Router position**
- The first step of every survey is "stand next to the router", which sets `router_x/y` [J].
- Finish asks the user to return to the router; the distance error = `loop_error_m` (drift indicator) [J].

**Handling**
- Hold the phone at chest height, screen facing you, throughout (guide step 2) [J].
- Body position changes RSSI [?: not in the inputs, but widely observed]. A consistent pose reduces noise.

## 8. Heatmap (IDW) [D: IDW first]

1. **Grid:** 0.5 m cells over the bounding box of samples + walls, plus 1 m padding [J].
2. **Aggregate:** for each cell, take the **median** RSSI of its samples (robust to spikes) [J]. A cell with ≥ 3 samples (proposed, [J]) = **measured**.
3. **Interpolate:** other cells get IDW from the 8 nearest measured cells within 5 m, power 2, in dBm [J]. These are **predicted**. Cells with no measured cell within 5 m are blank ("not measured").
4. **Render:**
   - Measured cells are solid; predicted cells are hatched and 50% opacity [D/J].
   - Walls are lines, the path is a thin trace, and spots are pins with labels.
   - Legend shows colour + word + pattern [D]. Tap any cell for its word, value and status.
5. **Known limitation:** IDW ignores walls, so it can smear signal through a concrete wall. The what-if model (§9B) accounts for walls; IDW stays the "map of what was measured".

Upgrade to a Gaussian process later [D].

## 9. Recommendations

**Shared inputs:** survey samples, router position, walls (traced or sketch), priority spots (labelled pins: desk, TV, bed [D: notes feature 3]; equal weight in MVP [J]), channel check.

- **Dead zone** = a connected group of ≥ 4 cells classed Dead zone [J].
- **Target** = each dead zone, plus each priority spot classed Weak or Dead.

**Card format [D]:** **What** · **Where** (pin + nearest room/wall label) · **Expected improvement**, tagged *Measured*, *Predicted (model)* or *Not estimated — re-walk to check*. Cost labels are tiers (Free / Low cost / Higher cost); **no prices** are shown (no source) [J]. Wording never says "boost".

**Ranking:** cost tier first (Free → Extender → Mesh) [D]. Within a tier, by number of targets improved, then predicted dB gain [J].

### 9A. Extender spot — tier: Low cost
- **Inputs:** router position, measured cells, each dead zone's centroid.
- **Method:**
  - For each dead zone, candidate cells = **measured** cells with median RSSI −65 … −60 dBm [D].
  - Keep candidates within 1.5 m of the segment router → centroid [J].
  - Pick the one nearest the dead zone.
  - No candidate → card says "Walk the area between the router and *[room]* again." Predicted cells are never used for this card [J].
- **Output:** "Put a Wi-Fi extender here. Signal at this spot is *Good* (measured)." Expected improvement is **Not estimated**: one phone cannot measure what the extender will deliver [D: notes] → suggest a re-walk after installing.

### 9B. Router what-if — tier: Free
- **Inputs:** samples with positions, router position, walls.
- **Model [D]:** log-distance path loss with per-wall attenuation:
  `RSSI(p) = P0 − 10·n·log10(d/1 m) − Σ L_w` over walls *w* crossed by the straight line router → *p*.
- **Fit [J]:**
  - The model is linear in the unknowns (P0, n, L_w), so solve with least squares and a ridge penalty pulling each L_w toward a shared mean. Walls with few samples behind them then fall back to the average.
  - Samples within 1 m of the router are excluded.
  - Small normal-equation solve in pure Dart; no dependency.
- **Quality gate [J]:**
  - Compute 5-fold cross-validated RMSE. If RMSE > 8 dB or fewer than 50 samples, S10 is disabled with "Not enough data to predict — walk more rooms."
  - The thresholds are proposed constants [?].
- **Method:**
  - The user drags the router (notes feature 1) to see a predicted heatmap.
  - The app also scores candidate cells inside the mapped area by: (1) priority spots predicted Good+, (2) dead-zone area.
- **Output:** "Move router to *[spot]*. Predicted: desk Weak → Good; dead zone area 9 m² → 3 m²." Always tagged *Predicted* and paired with "Confirm with Hotspot test or a re-walk."
- **Limits stated in UI:** untraced walls, furniture, floors and router height are not modelled.

### 9C. Laptop Mobile Hotspot test — tier: Free
- **Inputs:** 2–3 named candidate spots (pins); priority spots; a Windows laptop with Mobile Hotspot [D].
- **Method:**
  1. Place the laptop at candidate A and connect the phone to its hotspot. The app confirms the connected AP changed (needs location), or the user confirms manually.
  2. At each priority spot, tap its pin and hold still; the app records a 5 s median [J].
  3. Repeat for B (and C) with the same laptop settings and orientation [J].
  4. Compare **relatively** only (laptop power differs from the router) [D]. Per spot, rank candidates. Score = mean of per-spot differences vs. the best candidate.
- AR is not required; positions come from the pins, so this works in manual mode.
- **Output:** "Spot B gave the strongest signal at 3 of 4 priority spots (on average 7 dB better than A)." Tagged *Measured (relative)*. Absolute router predictions are never derived from it.

### 9D. Other free fixes and mesh
- **Channel:**
  - If the connected network's channel has ≥ 3 strong neighbours and another channel has fewer, show "Change the Wi-Fi channel in your router settings" [J; "channel" is a notes fix].
  - Improvement: **Not estimated**.
- **Band / antennas:** shown as checklist tips (notes fixes) with **Not estimated** [J]. The claim that 2.4 GHz reaches farther than 5 GHz is outside the inputs [?]; word it as "try the other band and re-walk".
- **Mesh** — tier: Higher cost [D]:
  - Suggested when ≥ 2 dead zones lie in different directions from the router and no single extender spot covers them, or the what-if finds no router spot covering all priority spots [J].
  - Node spots come from the 9A method, one per zone.

## 10. ARCore-unsupported and tracking-loss fallback (full flow)

1. **On Scan tab open:** `ArCoreApk.checkAvailability()` [V].
   - `UNKNOWN_CHECKING` → recheck every 200 ms for up to 2 s [J]; then treat it as unknown → step 4 with "Try AR" retry.
2. **`SUPPORTED_INSTALLED`** → AR mode. **`SUPPORTED_NOT_INSTALLED` / `SUPPORTED_APK_TOO_OLD`** → card "Install Google Play Services for AR" → `requestInstall(activity, true)` [V]. Declined or failed → step 4.
3. **`UNSUPPORTED_DEVICE_NOT_CAPABLE`** [V] → step 4 permanently for this device, with "Your phone doesn't support AR. You can still map by sketching rooms."
4. **Manual mode:**
   1. S6: draw rooms as rectangles (name, width × length) on a grid; mark the router and priority spots.
   2. S5: stand somewhere, tap your position on the sketch, hold "Record" → 5 s median sample.
   3. The app prompts for at least 3 points per room [J].
   - Room edges become walls for §9B.
   - Heatmap, extender, what-if and hotspot all work unchanged; position precision is lower (shown as "Manual positions" badge).
5. **Camera permission denied** → same as step 4.
6. **Tracking loss during an AR scan:**
   - Sampling pauses and the banner shows the reason.
   - Messages for `INSUFFICIENT_LIGHT`, `INSUFFICIENT_FEATURES`, `EXCESSIVE_MOTION` [V] (e.g. "Too dark — turn on a light", "Point at a textured area, not a blank wall", "Move slower").
   - If not tracking for > 10 s [J], offer "Finish this room in manual mode". The scan becomes mixed; samples keep their `position_source`.
   - The notes warn that ARCore struggles in dark rooms and with plain white walls [D].

## 11. UI theme and accessibility

- **Dark first** "signal/radar" theme [D]:
  - background `#0A0F1C` (near-black navy), surface `#121A2B`, single accent cyan `#3DD6F5` [J]
  - light mode mirrors the tokens [D]
  - Material 3 `ColorScheme` with all colours as named tokens.
- **Heatmap:** green → yellow → red [D]. Each band also has a distinct pattern and a word label, so meaning never depends on colour alone [D].
- **Tap targets:** ≥ 48 dp; Start/Pause/Finish ≥ 64 dp tall in the bottom third for one-handed use [J; 48 dp is Android guidance, not fetched this run].
- **Contrast:** text ≥ 4.5:1 [J: WCAG AA; outside the listed inputs].
- **Font scale and TalkBack:** supports 200% font scale; TalkBack labels on meter ("Signal: Weak") and map cells.
- **Copy rule:** "measure", "check", "suggest" — never "boost", "fix your Wi-Fi automatically", or speed promises [D].

**Design direction (2026-11-20) [J].** Patterns taken from browsing Dribbble ("wifi analyzer app", "wifi signal strength dark"); patterns only, no design copied:
- *Radial gauge hero* (speed-test style): one large 240° arc on the Scan screen, the signal word big in the centre, dBm and band small underneath, arc and glow in the band colour, faint radar rings that pulse while recording.
- *Stats row* under the gauge: Time · Readings · Weakest, tabular figures.
- *Signal timeline:* last 60 s as a line over faint band stripes, so drops are visible without AR.
- *Floor-plan heatmap* (for M5): soft blobs over room outlines, router pin, compact bottom sheet for cell details.
- *Legend swatches:* colour + pattern (solid · dots · lines · cross-hatch) + word, shared by the legend and the heatmap.
- *Rounded cards* (20 dp), surface-container tones, accent used only for primary actions and the active tab.

## 12. Milestones (each ends with a real-phone test) [J order]

- [x] **M0 Skeleton** — Flutter project, 3 tabs, dark/light theme, `signalWord()` + tests, approved dependencies. *Phone:* installs, tabs switch, theme toggles; merged manifest has no `INTERNET`. Phone checks passed 2026-11-20; merged-manifest check still open.
- [x] **M1 Live signal** — `WifiSignalStreamHandler.kt` + `sagap/rssi`; S3/S4 meter without AR. *Phone:* walk away from the router; the word goes Excellent → Weak. Signal confirmed live on phone 2026-11-20 without location permission. Still open: log the real update rate (callback vs. poll source).
  - Pulled forward from M10: first-run guide with illustrations; settings saved in SQLite.
- [ ] **M2 AR spike** — *Built 2026-11-20, not verified on AR hardware.* ARCore 1.57.0 approved; AR Optional manifest; availability/install/camera flow; GLSurfaceView preview via Hybrid Composition; 5 Hz pose stream; mini-map with "From start" / "Walked" readouts for the tape test. Dev phone (itel S665L) is not on Google's ARCore device list and has no Google Play Services for AR, so only the fallback path can be checked on it. Fallback verified on that phone 2026-11-20: Scan shows "This phone doesn't support AR" (§10 step 3). Tape test, loop test and FPS decision need a supported phone.
  Original plan: **M2 AR spike** — availability flow, camera permission, AR view, pose stream, mini-map. *Phone:* walk a tape-measured 5 m line and a loop. Record the length error and loop-closure error. Decide PlatformView vs. native Activity on FPS.
- [ ] **M3 Samples + storage** — pairing, SQLite, S7 summary, Homes list. *Phone:* finish a scan, force-stop the app, reopen; the scan and sample count are intact. *Built 2026-11-20:* pairing (AT6), Save/Discard with home choice, Homes list, home detail with rename/delete. Widget tests use an in-memory repository; the SQLite code is checked on the phone only.
- [ ] **M4 Walls, router, spots** — corner tap + "mark here", router step, priority pins, loop check. *Phone:* trace one room; wall lengths roughly match a tape measure.
- [ ] **M5 Heatmap** — IDW in isolate, measured/predicted rendering, legend, cell inspect. *Phone:* map 2+ rooms; check 3 spots against the live meter. *Built 2026-11-20 (unit + widget tested, not yet on phone):* grid / median / IDW per §8 (AT10 passes); Map tab picks any saved AR or sketch scan; measured cells solid, predicted faded to 45 %; band patterns on every cell; tap a cell for word · dBm · measured/predicted. Changes from plan:
  - Sketch spots count as measured with **1** sample (each is already a 5-reading median); AR keeps the 3-sample rule.
  - IDW runs on the UI isolate, not a separate one. The grid is capped at 40,000 cells (the cell size doubles beyond that), which keeps it small. Move it to an isolate if the phone stutters.
  - Predicted cells are faded, not hatched, so they don't clash with the band patterns. The legend says "Faded = predicted".
- [ ] **M6 Manual fallback** — S6 sketch, S5 tap-to-record, tracking-loss handoff. *Phone:* force manual via a debug flag; produce a heatmap without AR. *Built 2026-11-20 (widget-tested, not yet on phone):*
  - Sketch editor: rooms as rectangles (1–30 m, 0.5 m grid, drag to move), router, priority spots. Each edit is saved immediately (schema v3).
  - Manual scan: tap "you are here", then **Record here** = median of 5 readings. Coverage prompt for rooms with < 3 spots; Undo. Saved to the sketched home as mode `manual`.
  - Not built: the tracking-loss handoff from AR to manual mid-scan (needs an AR phone to test). A debug flag isn't needed: the dev phone has no AR.
- [ ] **M7 Fixes I** — extender (9A), channel check with scan budget, tips, mesh rule, ranked cards (S9). *Phone:* a real home produces cost-ordered cards; scans never exceed budget. *Built 2026-11-20 (Dart unit + widget tested; Kotlin `WifiScanHandler` not compile-checked: Gradle fails in this environment with "Unable to establish loopback connection"):*
  - **Dead zones:** ≥ 4 four-connected Dead-zone cells, measured or predicted. **Targets:** dead zones plus priority spots that are Weak or Dead.
  - **Extender:** a measured cell at −65…−60 dBm within 1.5 m of the router → target line, nearest the target. Several targets served by one spot share a card. With no spot found, the card says to walk that area again. Improvement is "not estimated: re-walk".
  - **Mesh:** ≥ 2 targets more than 90° apart (seen from the router), with no single extender spot covering them. Node pins come from the extender spots.
  - **Channel:** Kotlin returns per-frequency counts of other networks at ≥ −70 dBm (no SSID/BSSID leaves Kotlin). Checks run at Start and Finish only; the app budget is 4 per 2 min (AT18). Advice is given when ≥ 3 neighbours share our channel and another channel seen in the same band has fewer. With no check, the card is a manual "check your channel" tip.
  - **Tips:** other band, antenna angle (from the notes); improvement not estimated.
  - **Router position:** sketch scans use the sketched router. AR scans use the walk's first position, and the card says so. AR and sketch coordinates are never mixed.
  - **Location:** asked once per app launch at Start, with a reason dialog; "Not now" only disables the channel check.
  - Cards are ranked by tier, then by targets helped (AT17). Prices are never shown.
- [ ] **M8 Router what-if** — fit, quality gate, S10 drag. *Phone:* fit on a real walk and show the RMSE. Then move the real router to the suggested spot, re-walk, and compare. *Built 2026-11-20 (unit + widget tested; AT14 and AT15 pass):*
  - **Walls:** the sketched room edges. Collinear touching or overlapping edges merge into one wall, so a shared wall counts once. AR scans have no walls until wall tracing (M4), so they fit distance only.
  - **Fit:** ridge least squares on P0, n, a shared wall loss L and per-wall δ (ridge 2 on δ only). Readings within 1 m of the router are skipped. Walls nobody stood behind get 0 dB, and learned losses are floored at 0 dB.
  - **Quality gate:** 5-fold cross-validated RMSE ≤ 8 dB, n between 1 and 6, and at least 50 readings for AR or **10 spots for sketch scans** [J: each spot is already a 5-reading median, so 50 would be unrealistic].
  - **"Move the router" card:** Free tier, tagged Predicted. It searches candidate spots every 1 m inside the sketched rooms (or the mapped area for AR), ranked by most priority spots Good or better, then least dead-zone area. It's shown only when the result is clearly better (more Good spots, or ≥ 0.5 m² less dead zone). It always says "Confirm with the hotspot test or a re-walk".
  - **S10 screen:** tap or drag to move the router, a predicted map (all faded), the change summary ("Desk Dead zone → Good; dead zones 9.0 m² → 0.0 m²"), Best spot, Reset, the model's ± error and reading count, and the limits text. When the gate fails it's disabled with the reason.
  - **Router position:** same rule as M7 (sketch router, or the AR walk's start).
- [ ] **M9 Hotspot test** — S11 flow and results card. *Phone + laptop:* compare 2 candidate spots. *Built 2026-11-20 (unit + widget tested; AT16 passes end to end):*
  - **Entry and setup:** Homes → a home → laptop icon. Needs ≥ 1 priority spot on the sketch, otherwise it asks you to add one. Tap 2–3 candidate spots (A/B/C pins, snapped to the grid).
  - **Per candidate:** instructions to put the laptop there with the same hotspot settings each time; a "This phone is connected to the laptop hotspot" checkbox (the user confirms; the app does not read network names); live signal word; then **Record** each priority spot = median of 5 readings, with Redo and Cancel.
  - **Results:** the AT16 sentence, a per-spot list with "Best", the relative-only caveat, and a reminder to reconnect to home Wi-Fi. Save or Discard (Discard asks first).
  - **Comparison:** spots measured for every candidate; score = mean (reading − best at that spot); ties go to the earlier candidate. The gain shown is the winner's mean against the runner-up.
  - **Fixes card:** "Router spot B tested best", Free, tagged **Measured (relative)**, from the home's newest test. Its pin shows only on sketch scans, because AR coordinates differ.
- [ ] **M10 Polish** — first-run guide art, all permission-denied paths, TalkBack + 200% font pass, battery measurement over a 10-min scan. *Built 2026-11-20, except the battery measurement (needs the phone):*
  - **Accessibility checks:** Flutter's `androidTapTargetGuideline`, `labeledTapTargetGuideline` and `textContrastGuideline` pass on Scan, Map, Fixes, Homes, home detail, Settings and the guide, in dark and light.
  - **200 % text:** no overflow on Scan (idle and recording), Map, Fixes, Homes, Settings, the guide, and hotspot setup. Fixes made: the guide pages scroll; the sketch editor and hotspot setup use `SplitCanvasLayout`, where the header and footer scroll in a capped share so the canvas keeps its space and drag gestures.
  - **Settings:** a Permissions section (camera and location status, what each is for and what happens without it, **Open Android settings**, re-checked on return); **Delete all data** with confirmation (keeps theme); privacy text no longer mentions a report export that doesn't exist.
  - **Battery:** a "Long scan" card after 15 min of recording (§14).
  - **Rule tests:** AT21 (no "boost" in `lib/`); AT22 (main manifest has no `INTERNET`; debug and profile have it for Flutter tooling); no `"ssid"` or `"bssid"` keys in any Kotlin result map.

**Build status (2026-11-20).**
- **Verified on the itel S665L (Android 12):** M0 and M1 (tabs, theme, live signal without location), and the M2 fallback ("doesn't support AR").
- **Tests:** 203 automated tests pass and `flutter analyze` is clean.
- **Not yet verified:**
  - M3 onward on the phone, including the database migrations v1 → v5.
  - Kotlin `WifiScanHandler` (M7/M10): never compiled, because Gradle fails in the agent environment with "Unable to establish loopback connection".
  - AR tracking (M2) on a supported phone.
  - The merged release manifest (do libraries add `INTERNET`?).
  - The battery measurement.
- **Not built:**
  - M4 (AR wall tracing and the router step).
  - The AR → manual handoff mid-scan.
  - Everything marked Later (before/after proof, Taglish report and export, Gaussian process, multi-floor).

The 2–3-week target is tight for M0–M10 [J]. M0–M7 is the minimum MVP; M8–M9 may slip.

## 13. Acceptance tests

| Feature | Test | Type |
|---|---|---|
| Signal words | AT1: −59 → Excellent, −60 → Good, −69 → Good, −70 → Weak, −79 → Weak, −80 → Dead zone, +5 / −120 → invalid | Unit |
| Tabs + theme | AT2: 3 tabs reachable; theme persists across restart | Widget + phone |
| First-run guide | AT3: shows once, 3 steps, skip works, replayable from S13 | Widget |
| Live RSSI | AT4: meter updates ≥ once per 2 s while walking; invalid values dropped | Phone |
| AR availability | AT5: each `Availability` value (faked) routes to the right screen per §10 | Unit (fake channel) |
| Sample pairing | AT6: RSSI at t=1000 ms with poses at 650/1250 → pairs with 1250 (Δ250 ≤ 300); with poses at 600/1400 → dropped | Unit |
| Tracking loss | AT7: non-TRACKING poses produce no samples; > 10 s loss shows manual offer | Unit + phone |
| Storage | AT8: scan survives force-stop; deleting a home deletes its scans/samples | Integration + phone |
| No identifiers | AT9: DB dump and logcat during a scan contain no SSID/BSSID | Phone |
| Heatmap IDW | AT10: two measured cells (−50 at x=0, −70 at x=2 m), cell at x=1 m → −60; cell 6 m away → blank | Unit |
| Measured vs predicted | AT11: cell with 3 samples renders solid; with 0 renders hatched | Widget/golden |
| Legend not colour-only | AT12: legend shows words + patterns; TalkBack reads cell word | Widget + phone |
| Extender | AT13: synthetic map with cells at −62 on the router→zone line → that cell chosen; none in band → "walk again" card | Unit |
| Path-loss fit | AT14: data generated with P0=−30, n=3, one wall L=10 dB → fit recovers each within ±0.5 | Unit |
| What-if gate | AT15: 40 samples → simulator disabled with reason | Unit |
| Hotspot compare | AT16: A = [−55, −70], B = [−60, −62] at 2 spots → B wins 1 of 2, mean diff reported correctly | Unit |
| Card ranking | AT17: Free cards always precede Extender, which precede Mesh | Unit |
| Channel budget | AT18: 5th scan request inside 2 min is refused by the app's counter | Unit |
| Permissions | AT19: deny camera → manual mode; deny location → live map + "channel check unavailable" | Phone |
| Manual mode | AT20: 3 rooms sketched + 9 taps → heatmap renders | Phone |
| Copy rule | AT21: grep of string resources finds no "boost" | Unit |
| Offline | AT22: release merged manifest lacks `INTERNET` (or the exception is documented) | Build check |

## 14. Risks and mitigations

| Risk | Mitigation |
|---|---|
| **AR drift** | Start and end at the router, report `loop_error_m`, and warn above 1 m [J]; short guided loops; drop non-TRACKING poses. |
| **RSSI noise** (body, orientation, fluctuation) | Median per cell; minimum 3 samples for "measured"; fixed holding pose; 5 s medians for spot readings; never recommend from a single sample. |
| **Scan throttling** (4 / 2 min [V]) | Live map uses connected RSSI only [D]; app-side budget counter; 2 scans per survey; cached results otherwise. |
| **Battery / heat** (camera + GL + Wi-Fi) | Stop the camera on Pause; pose at 5 Hz, not per frame; nudge to finish after 15 min [J]; measure in M10. |
| Dark rooms / white walls [D] | Specific tracking messages; per-room manual handoff. |
| Platform-view FPS [V] | Decide in M2; native Activity fallback. |
| RSSI may need location | Not needed on the one phone tested (Android 12). Re-check on Android 13+ when possible. |
| What-if overfitting | Ridge toward a shared wall loss; cross-validation gate; always "Predicted". |
| Green–red colour blindness | Patterns + words + inspect. |
| Timeline | M0–M7 is the minimum MVP; AR spike early (M2) to surface risk. |

## 15. Conflicts, unknowns, and the case against ARCore

**Conflicts / deviations**
1. The notes mark the whole idea **"on hold … still looking for a more unique, globally useful idea"**; the brief proceeds to build it. I treated the brief as your current decision. Please confirm.
2. The notes' fallbacks include **step counter + compass**; the brief names hand-drawn rooms + tap-to-record. Both agree on hand-drawn rooms. The step counter is placed in **Later** (the notes flag it as drifting); not a contradiction.
3. Android docs: one page says `neverForLocation` removes the need for FINE_LOCATION, while the same page says scan APIs still need it on 13+ [V]. The spec follows the stricter reading.

**Undecided — needs your call (MVP or Later?)**
- Before/after proof (notes feature 2)
- Shareable Taglish report (feature 6) and the export format
- Priority-spot weighting (feature 3)
- UI language (English vs Taglish)
- Multi-floor homes

**Unknowns [?]**
- RSSI permission needs and real update rate
- Invalid RSSI value
- Whether `onCapabilitiesChanged` fires per RSSI change
- ARCore Y-up axis
- EventChannel (not on the fetched page)
- Normal-permission levels
- Signal-word thresholds
- All [J] numeric constants

**Strongest argument against ARCore (riskiest choice)**
- It is the hardest part for you (new to ARCore and platform channels), and it may not serve the target users well:
  - It requires a supported phone [D, V]. Students and renters may have phones it doesn't support.
  - It struggles in dark rooms and with plain white walls [D].
  - It adds camera battery drain, and Flutter's platform view reduces FPS [V].
- AR could consume half the 2–3-week budget while manual mode ends up the path most users actually take.
- **Why keep it anyway:** it is the stated differentiator (no floor plan, one walk) [D].
- **How the spec hedges:**
  - AR sits behind an interface.
  - Manual mode is a first-class path producing the same data.
  - The AR spike is M2, so you learn early whether to pivot to manual-first.

## 16. Sources

- `app-ideas-notes.md` (pasted 2026-11-19), the brief, CLAUDE.md
- developer.android.com: `develop/connectivity/wifi/wifi-scan`, `wifi-permissions`, reference `WifiManager`, `WifiInfo`, `NetworkCapabilities`
- developers.google.com/ar: `develop/java/enable-arcore`, reference `ArCoreApk.Availability`, `TrackingFailureReason`, `Pose`
- docs.flutter.dev: `platform-integration/platform-channels`, `platform-integration/android/platform-views`
