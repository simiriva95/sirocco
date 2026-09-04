# Changelog

## 0.6.0 — 2026-09-03

- 14-day trial from first launch (install date kept in UserDefaults and Application Support,
  earliest wins; clock rollback does not revive it). After that, popover and window show a
  lock screen; sampling drops to the menu bar icon only.
- Owner unlock with a password: salted PBKDF2-HMAC-SHA256 (200k iterations) hash embedded at
  build time via `make unlock-hash`; unlock from the lock screen or Settings › License.
- Public download repository `sirocco-releases`; `make release` publishes there.

## M5 — 2026-09-03

- Overview tab: diagnosis banner, CPU / memory / thermal cards with 5-minute history, top five
  by CPU / memory / energy with one-click navigation to the process, disk and network footer.
- Settings: appearance (system/light/dark), interval at rest (1/2/5 s), CPU attention/critical
  thresholds (drive popover and overview colors), memory units, user protected processes
  (matched on p_comm and app name), shortcut reference.
- Design system: one `cardBackground()` surface, one `Format` for bytes/rates/percent, Increase
  Contrast borders. Localization audit: Italian complete.

## M4 — 2026-09-03

- Sensors tab: temperatures (CPU die / GPU / SSD, 5-minute history), fans with SMC min/max,
  system / adapter / battery power (W), battery status, raw sensor list. Sources probed once
  at first use; unavailable sources are reported, never faked.
- `SensorSource` protocol with `HIDTemperatureSource` (private IOHID), `SMCSource`, `BatterySource`.
- Startup tab: user LaunchAgents with enable/disable, system agents and daemons read-only,
  link to Login Items settings.
- Sensors sampled only while the Sensors tab is visible.

## M3 — 2026-09-03

- Performance tab: 1/5/15 min windows; CPU total + P/E lines and per-core heatmap grouped by
  kind; memory stacked (app / wired / compressed / cached) against physical RAM with swap line;
  disk read/write; network for the three busiest interfaces (↓/↑); thermal state strip.
- Shared chart engine (`TimeSeriesChart`, `CoreHeatmap`, `ChartCard`): one grid, one axis, one
  time mapping by absolute timestamps, so cadence changes never distort the x axis.
- Sampling: disk (`IOBlockStorageDriver`) and network (`getifaddrs`) counters every tick,
  32-bit wraparound handled; one aligned `PerformanceSample` history of 900 entries.
- Fix: rows in the popover and the Processes table hold their order while the pointer is over them.

## M2 — 2026-09-03

- Main window (AppKit-owned, SwiftUI content): app switches Dock/menu presence on open/close.
- Processes tab: `NSOutlineView` with sortable, reorderable, hideable, autosaved columns
  (name, pid, energy, CPU, memory, threads, wakeups, disk read/write, user); apps grouped with
  their helpers as expandable rows with totals; search by name or pid; details inspector.
- Terminate / Force Quit from context menu, inspector, or ⌘⌫ / ⌘⌥⌫ with group confirmation.
- Keyboard: ⌘1…⌘5 tabs, ⌘F search, ↩ details, ⌘O open window; global hotkey ⌃⌥S for the popover.
- Thread counts (`PROC_PIDTASKINFO`) sampled only while the Processes tab is visible.
- Cadence: main window samples at 2 s; deterministic pid tie-break in all sorts.

## M1 — 2026-09-03

- Menu bar item with runtime-drawn sparkline (auto-ranged) and thermal glyph; template image in
  nominal state, shape + color for attention/critical.
- Popover: diagnosis sentence, CPU (with P/E split) / memory / thermal mini-charts, top 8 app
  groups by energy impact, search, SIGTERM with explicit SIGKILL escalation after 3 s.
- `EnergyImpactModel.v1`: cpu×100 + pkg wakeups×0.5 + interrupt wakeups×0.05 + disk MB/s×0.5.
- Sampling: 1 s / 2 s / 5 s / suspended cadence, ×2 under critical thermal state.
- Localization IT + EN; unit tests for metrics, diagnosis, grouping and kill policy (23).
