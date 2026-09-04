import SwiftUI

struct SensorsTab: View {
    @Environment(MetricsStore.self) private var store

    var body: some View {
        ScrollView {
            if let sensors = store.sensors {
                VStack(alignment: .leading, spacing: DS.Spacing.m) {
                    HStack(alignment: .top, spacing: DS.Spacing.m) {
                        temperaturesCard(sensors)
                        fansCard(sensors)
                    }
                    HStack(alignment: .top, spacing: DS.Spacing.m) {
                        powerCard(sensors)
                        batteryCard(sensors.battery)
                    }
                    allSensorsCard(sensors)
                    Text(sensors.availableSources.isEmpty
                         ? String(localized: "Not available on this Mac")
                         : String(localized: "Sources: \(sensors.availableSources.joined(separator: ", "))"))
                        .font(DS.Typography.secondary).foregroundStyle(.secondary)
                    Text("Temperatures come from private Apple sensors and may stop working after a macOS update.")
                        .font(DS.Typography.secondary).foregroundStyle(.secondary)
                }
                .padding(DS.Spacing.l)
            } else {
                ContentUnavailableView(String(localized: "Waiting for sensors…"), systemImage: "thermometer.medium").frame(minHeight: 300)
            }
        }
    }

    // MARK: Cards

    private func temperaturesCard(_ sensors: SensorSnapshot) -> some View {
        let history = store.sensorHistory.elements
        let now = sensors.timestamp
        let series = [
            (String(localized: "CPU die"), Color.orange, history.compactMap { s in s.cpuDieCelsius.map { (s.timestamp, $0) } }, sensors.cpuDieCelsius),
            (String(localized: "GPU"), Color.purple, history.compactMap { s in s.gpuCelsius.map { (s.timestamp, $0) } }, sensors.gpuCelsius),
            (String(localized: "SSD"), Color.teal, history.compactMap { s in s.ssdCelsius.map { (s.timestamp, $0) } }, sensors.ssdCelsius),
        ].filter { !$0.2.isEmpty }
        return ChartCard(title: String(localized: "Temperatures"), value: sensors.cpuDieCelsius.map(celsius) ?? "—",
                         legend: series.map { ($0.0, $0.1, $0.3.map(celsius) ?? "—") },
                         accessibilitySummary: series.map { "\($0.0) \($0.3.map(celsius) ?? "—")" }.joined(separator: ", ")) {
            if series.isEmpty {
                unavailable
            } else {
                TimeSeriesChart(series: series.map { ChartSeries(id: $0.0, label: $0.0, color: $0.1, points: $0.2) },
                                window: 300, now: now, yMax: 110, formatY: { "\(Int($0))°" }).frame(height: 130)
            }
        }
    }

    private func fansCard(_ sensors: SensorSnapshot) -> some View {
        ChartCard(title: String(localized: "Fans"), value: sensors.fans.isEmpty ? "" : rpm(sensors.fans.map(\.value).max() ?? 0),
                  accessibilitySummary: sensors.fans.map { "\($0.name) \(rpm($0.value))" }.joined(separator: ", ")) {
            if sensors.fans.isEmpty {
                Text("No fans (or the SMC does not expose them).").font(DS.Typography.secondary).foregroundStyle(.secondary).frame(height: 130)
            } else {
                VStack(alignment: .leading, spacing: DS.Spacing.s) {
                    ForEach(sensors.fans) { fan in
                        let limits = sensors.fanLimits[fan.id]
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(fan.name)
                                Spacer()
                                Text(rpm(fan.value)).font(DS.Typography.value)
                            }
                            GeometryReader { geo in
                                let fraction = limits.map { l in l.max > 0 ? min(max(fan.value / l.max, 0), 1) : 0 } ?? 0
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.quaternary)
                                    Capsule().fill(DS.color(fraction > 0.85 ? .critical : fraction > 0.5 ? .attention : .nominal))
                                        .frame(width: geo.size.width * fraction)
                                }
                            }
                            .frame(height: 6)
                            if let limits {
                                Text("\(rpm(limits.min)) – \(rpm(limits.max))").font(DS.Typography.secondary).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(minHeight: 130, alignment: .top)
            }
        }
    }

    private func powerCard(_ sensors: SensorSnapshot) -> some View {
        let history = store.sensorHistory.elements
        let points = history.compactMap { s in s.systemPowerWatts.map { (s.timestamp, $0) } }
        return ChartCard(title: String(localized: "Power"), value: sensors.systemPowerWatts.map(watts) ?? "—",
                         legend: sensors.readings.filter { $0.kind == .power }.enumerated().map { ($0.element.name, [Color.blue, .orange, .green][$0.offset % 3], watts($0.element.value)) },
                         accessibilitySummary: sensors.systemPowerWatts.map { String(localized: "System power") + " " + watts($0) } ?? String(localized: "Not available on this Mac")) {
            if points.isEmpty {
                unavailable
            } else {
                TimeSeriesChart(series: [ChartSeries(id: "pstr", label: String(localized: "System power"), color: .blue, points: points)],
                                window: 300, now: sensors.timestamp, yFloor: 10, formatY: { "\(Int($0)) W" }).frame(height: 130)
            }
        }
    }

    private func batteryCard(_ battery: BatteryStatus?) -> some View {
        ChartCard(title: String(localized: "Battery"), value: battery.map { "\(Int($0.chargePercent.rounded()))%" } ?? "",
                  accessibilitySummary: battery.map { batterySummary($0) } ?? String(localized: "No battery in this Mac.")) {
            if let battery {
                Grid(alignment: .leading, horizontalSpacing: DS.Spacing.m, verticalSpacing: DS.Spacing.xs) {
                    row(String(localized: "Charge"), "\(Int(battery.chargePercent.rounded()))%")
                    row(String(localized: "Health"), battery.healthPercent.map { "\(Int($0.rounded()))%" } ?? "—")
                    row(String(localized: "Cycles"), String(battery.cycleCount))
                    row(battery.isCharging ? String(localized: "Charging") : battery.externalPower ? String(localized: "On AC power") : String(localized: "Discharging"),
                        watts(abs(battery.watts)))
                    row(String(localized: "Time remaining"), battery.minutesRemaining.map { String(localized: "\($0 / 60) h \($0 % 60) min") } ?? "—")
                    row(String(localized: "Battery temperature"), battery.temperatureCelsius.map(celsius) ?? "—")
                }
                .frame(minHeight: 130, alignment: .top)
            } else {
                Text("No battery in this Mac.").font(DS.Typography.secondary).foregroundStyle(.secondary).frame(height: 130)
            }
        }
    }

    private func allSensorsCard(_ sensors: SensorSnapshot) -> some View {
        let temperatures = sensors.readings.filter { $0.kind == .temperature }
        return ChartCard(title: String(localized: "All sensors"), value: "\(temperatures.count)", accessibilitySummary: "\(temperatures.count)") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(temperatures) { reading in
                    HStack {
                        Text(reading.name).lineLimit(1).foregroundStyle(.secondary)
                        Spacer()
                        Text(celsius(reading.value)).monospacedDigit()
                    }
                    .font(DS.Typography.secondary)
                }
            }
        }
    }

    // MARK: Helpers

    private var unavailable: some View {
        Text("Not available on this Mac").font(DS.Typography.secondary).foregroundStyle(.secondary).frame(height: 130)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
        .font(DS.Typography.label)
    }

    private func batterySummary(_ b: BatteryStatus) -> String {
        "\(Int(b.chargePercent.rounded()))%, \(String(localized: "Cycles")) \(b.cycleCount), \(watts(abs(b.watts)))"
    }

    private func celsius(_ value: Double) -> String { String(format: "%.1f °C", value) }
    private func watts(_ value: Double) -> String { String(format: "%.1f W", value) }
    private func rpm(_ value: Double) -> String { String(localized: "\(Int(value.rounded())) rpm") }
}
