# Changelog

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
