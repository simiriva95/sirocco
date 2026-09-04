# Sirocco

A system monitor and task manager for macOS with Windows-Task-Manager coverage and the
conventions of a modern Mac app. Built for one question first: **"my Mac is getting hot,
why, and how do I stop it?"**

- **Menu bar**: a live sparkline plus a thermal glyph, drawn at runtime. One click opens a
  popover with a one-sentence diagnosis, CPU / memory / thermal mini-charts, the top
  consumers grouped by app, and inline terminate (SIGTERM, explicit escalation to SIGKILL).
- **Main window**: Overview, Processes, Performance, Sensors, Startup. The Processes tab is
  complete: sortable, reorderable, hideable columns (right-click the header), search, apps
  grouped with their helpers as expandable rows, a details inspector, terminate / force quit.
  Everything works from the keyboard: ⌘1…⌘5 tabs, ⌘F search, ↩ details, ⌘⌫ terminate,
  ⌘⌥⌫ force quit, ⌃⌥S toggles the popover from anywhere.

- **Performance tab**: 1 / 5 / 15-minute sliding windows, no persistence. CPU total with the
  Performance/Efficiency split and a per-core heatmap, memory stacked by type, disk read/write,
  network per interface, thermal state over time. All charts are hand-drawn `Canvas` code
  sharing one axis/grid implementation.

- **Sensors tab**: CPU die / GPU / SSD temperatures with history, fan RPM against the SMC's
  min/max, system power in watts, battery charge / health / cycles / time remaining, and the
  full raw sensor list. Every card says "Not available on this Mac" instead of showing zeros.
- **Startup tab**: user LaunchAgents (toggle on/off), system LaunchAgents and LaunchDaemons
  (read-only), a shortcut to the Login Items settings pane.

Status: **M4** (menu bar, Processes, Performance, Sensors, Startup) — usable daily, not yet a product.

## Install

Sirocco is not on the App Store and cannot be: a sandboxed app cannot list, inspect or
signal other processes. Two options:

**From GitHub Releases** — download `Sirocco.zip`, unzip, move `Sirocco.app` to
`/Applications`. Phase-1 builds are ad-hoc signed and not notarized, so Gatekeeper will
refuse the first launch; clear the quarantine flag once:

```bash
xattr -dr com.apple.quarantine /Applications/Sirocco.app
```

**From source** — requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`):

```bash
git clone https://github.com/simiriva95/sirocco.git && cd sirocco
make build      # → dist/Sirocco.app and dist/Sirocco.zip
```

`make dev` builds Debug and launches; `make test` runs the unit tests.

Requirements: macOS 14+, Apple Silicon (arm64 only — Intel is not supported).

## What it measures, and why these sources

| Metric | Source | Notes |
|---|---|---|
| CPU per core | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`, delta between samples | Cores mapped to Performance / Efficiency via `hw.perflevel*.logicalcpu` (E cores come first in the logical numbering). |
| Memory | `host_statistics64` + `vm.swapusage` + `kern.memorystatus_vm_pressure_level` | "Used" = app (internal − purgeable) + wired + compressed, like Activity Monitor. `total − free` is meaningless on macOS. |
| Thermal state | `ProcessInfo.thermalState` | Public API, no privileges, four levels. Always works. |
| Temperatures | private `IOHIDEventSystemClient`, usage page `0xff00` / usage 5 | Names differ per chip (`PMU tdie*` on M3/M4, `pACC MTR Temp Sensor*` on M1); grouped by prefix, garbage (−9201 °C) filtered, duplicates collapsed to the hottest. Behind `SensorSource`; may vanish with a macOS update. |
| Fans, system power | `AppleSMC` user client: `FNum`, `F*Ac/Mn/Mx`, `PSTR`, `PDTR`, `PPBR` | Undocumented keys; each read may return nothing. Read-only, no fan control. |
| Battery | `AppleSmartBattery` IORegistry | Health = `AppleRawMaxCapacity / DesignCapacity`; watts = voltage × amperage. |
| Per-process CPU, wakeups, disk I/O | `proc_pid_rusage(RUSAGE_INFO_V4)` as deltas | Times are mach absolute units; converted with `mach_timebase_info`. |
| Per-process memory | `ri_phys_footprint` | What Activity Monitor calls "Memory". RSS is kept but not shown. |
| Process list | one `sysctl(KERN_PROC_ALL)` into a reused buffer | No per-tick allocation once the process count is stable. |
| Disk throughput | `IOBlockStorageDriver` → `Statistics` (`Bytes (Read)` / `Bytes (Write)`), delta | Physical drives, not volumes. |
| Network throughput | `getifaddrs` → `if_data` per interface, delta | Counters are 32-bit and wrap every 4 GB; the delta code knows. Loopback excluded. |
| App grouping | `responsibility_get_pid_responsible_for_pid` | Exported by libSystem, no public header. Used only for grouping. |

### Energy impact

The number next to each process is `EnergyImpactModel.v1`, defined in one file and versioned:

```
impact = cpu_fraction × 100          (100 = one core saturated)
       + package_idle_wakeups/s × 0.5
       + interrupt_wakeups/s    × 0.05
       + disk_MB/s              × 0.5
```

Activity Monitor's "Energy Impact" additionally weighs GPU time and QoS, which are not
readable per process through public API. Expect our ranking to agree with Activity
Monitor on CPU-bound and wakeup-heavy processes and to under-rank GPU-heavy ones — that is
also why the diagnosis names `WindowServer` as "graphics" instead of attributing it.

### Diagnosis

`DiagnosisEngine` is a pure function of the last minute: thermal history, CPU history and
the current process samples. Rules, in order:

1. Thermal state `.serious` / `.critical` for ≥ 20 s → **Hot for N min. Likely cause: A + B**,
   where A (+ B) are the fewest top processes covering 60 % of total impact.
2. Thermal `.fair` → **Warming up. Top consumer: A**.
3. CPU ≥ 75 % for the last 10 samples without heat → **CPU under load**.
4. Otherwise **All quiet**.

No prose lives in the engine; the view localizes a structured verdict.

## Overhead

Measured on an M4 Pro (macOS 26.3) with Sirocco's own process row and `top`, Release build:

| State | CPU | Footprint |
|---|---|---|
| Menu bar only, 2 s sampling | 0.1–0.3 % | 15 MB |
| Popover open, 1 s sampling, ~800 processes | 1.0–1.4 % | ~40–150 MB (SwiftUI + app icons) |
| Processes window open, 2 s sampling, ~300 rows + threads | 2.0–3.7 % | ~60–70 MB |
| Performance tab open, 2 s sampling, five charts + 14-core heatmap | 1.4–2.2 % | ~160 MB |
| Sensors tab open, 2 s sampling, 76 HID sensors + SMC + battery | 1.6–2.4 % | ~150 MB |

Sampling cadence: 1 s with the popover open, 2 s at rest or with the main window (Activity
Monitor defaults to 5 s), 5 s when nothing is visible, suspended while the screens sleep,
and **doubled** under `.critical` thermal state — a monitor must consume less when the
machine is hot, not more.

The Processes table is an `NSOutlineView`, not a SwiftUI `Table`. Measured in Release: the
SwiftUI table re-inserted rows with automatic heights on every tick (8–9 % CPU); the
outline view gets fixed-height rows, item objects reused across ticks, text updated only
where it changed, and sort keys quantized to the displayed precision so rows do not swap
over invisible jitter. Live re-sorting is the remaining cost, which is why the window
samples at 2 s.

Longevity check for M1: 2.5 minutes of opening/closing the popover every 2 s
(`SIROCCO_POPOVER=cycle`), then `leaks` → `0 leaks for 0 total leaked bytes`. All histories
are fixed-capacity ring buffers (900 samples); the icon cache is pruned against the live pid
set on every tick.

## Known limits (by design)

- **No per-process network.** macOS offers no public API for it; the alternatives are a
  network extension or private frameworks. There is no empty column for it.
- **Private sensors may not work on your chip.** Temperatures and fan RPM (M4) come from
  `IOHIDEventSystemClient` / SMC, private and different across chip generations. The
  Sensors tab will say "not available" rather than show zeros.
- **Processes of other users** show up but cannot be terminated without admin rights;
  Sirocco says so instead of failing silently. Protected system processes (`kernel_task`,
  `launchd`, `WindowServer`, `loginwindow`, `coreaudiod`, `mds*`, `backupd`, Sirocco
  itself) are never signalled.
- **Startup items**: user LaunchAgents can be disabled (`launchctl disable` + `bootout`);
  system agents/daemons are read-only; login items live in the Background Task Management
  database, which is not readable without root, so the tab links to System Settings instead.
- **No fan control**, by design. Sensors are read-only.
- **Grouping follows macOS's notion of responsibility.** XPC services the system spawns on an
  app's behalf are attributed to that app, so Sirocco itself shows two or three "processes".
- **The global hotkey uses Carbon `RegisterEventHotKey`** (deprecated, still the only public
  API that needs no Accessibility permission). Fixed to ⌃⌥S until Settings grow a recorder.

## Development

```
Sources/
  Interop/        thin typed layer over sysctl, mach, libproc — the only Unsafe* code
  Metrics/        pure: ring buffer, CPU/memory models, process deltas, energy model, grouping
  Diagnosis/      pure: rules → structured verdict
  Sampling/       Sampler actor, cadence policy, main-actor MetricsStore
  Processes/      identity/icon cache, termination policy, terminator
  MenuBar/        NSStatusItem, Core Graphics icon renderer, SwiftUI popover, Carbon hotkey
  Windows/        AppKit-owned main window, NSOutlineView process table, Performance/Sensors/Startup tabs
  Sensors/        SensorSource protocol, classifier, hub (IOHID + SMC + battery behind it)
  Startup/        LaunchAgents/Daemons scanner, launchctl client, store
  DesignSystem/   tokens, sparkline geometry, TimeSeriesChart / CoreHeatmap / ChartCard
  Settings/       UserDefaults-backed settings, Settings scene
  Licensing/      LicenseGating protocol (stub; phase 2)
Tests/            Metrics, Diagnosis, aggregation, policies — fixtures, no I/O
```

Swift 6 with strict concurrency, SwiftUI + AppKit, zero third-party dependencies. The
Xcode project is generated from `project.yml`; never edit the `.xcodeproj`.

Debug switches: `SIROCCO_POPOVER=open|cycle` drives the popover without a mouse;
`SIROCCO_WINDOW=1|processes|performance|…` opens the main window (on a tab) at launch;
`SIROCCO_LOG_SELF=1` logs Sirocco's own cost via `os_log` (subsystem `it.simoneriva.sirocco`).

## License

Proprietary — see [LICENSE](LICENSE). Source is published for inspection and personal builds.
