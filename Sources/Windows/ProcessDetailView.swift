import SwiftUI

/// Inspector for the selected row: every per-process fact we have, plus the kill buttons.
struct ProcessDetailView: View {
    var samples: [ProcessSample]
    @Environment(MainWindowModel.self) private var model
    @Environment(MetricsStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                if samples.isEmpty {
                    ContentUnavailableView(String(localized: "No selection"), systemImage: "cursorarrow.click")
                } else if samples.count == 1, let sample = samples.first {
                    single(sample)
                } else {
                    group
                }
            }
            .padding(DS.Spacing.l)
        }
    }

    private func single(_ sample: ProcessSample) -> some View {
        let identity = store.identities.identity(for: sample)
        return VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack(spacing: DS.Spacing.s) {
                if let icon = identity.icon { Image(nsImage: icon).resizable().frame(width: 32, height: 32) }
                VStack(alignment: .leading) {
                    Text(identity.name).font(DS.Typography.title)
                    Text(identity.bundleIdentifier ?? sample.command).font(DS.Typography.secondary).foregroundStyle(.secondary)
                }
            }
            killButtons
            Grid(alignment: .leading, horizontalSpacing: DS.Spacing.m, verticalSpacing: DS.Spacing.xs) {
                fact(String(localized: "PID"), String(sample.pid))
                fact(String(localized: "Parent PID"), String(sample.parentPID))
                fact(String(localized: "User"), UserNames().name(for: sample.uid))
                fact(String(localized: "Energy"), sample.energyImpact.formatted(.number.precision(.fractionLength(1))))
                fact(String(localized: "% CPU"), (sample.cpuFraction * 100).formatted(.number.precision(.fractionLength(1))))
                fact(String(localized: "Memory (footprint)"), sample.physFootprintBytes.formatted(.byteCount(style: .memory)))
                fact(String(localized: "Resident (RSS)"), sample.residentBytes.formatted(.byteCount(style: .memory)))
                fact(String(localized: "Threads"), sample.threadCount.map(String.init) ?? "—")
                fact(String(localized: "Package wakeups/s"), sample.packageIdleWakeupsPerSecond.formatted(.number.precision(.fractionLength(0))))
                fact(String(localized: "Interrupt wakeups/s"), sample.interruptWakeupsPerSecond.formatted(.number.precision(.fractionLength(0))))
                fact(String(localized: "Read/s"), UInt64(sample.diskReadBytesPerSecond).formatted(.byteCount(style: .memory)))
                fact(String(localized: "Write/s"), UInt64(sample.diskWriteBytesPerSecond).formatted(.byteCount(style: .memory)))
            }
            if let path = ProcessEnumerator.path(pid: sample.pid) {
                Text(String(localized: "Path")).font(DS.Typography.secondary).foregroundStyle(.secondary)
                Text(path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
        }
    }

    private var group: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text("\(samples.count) processes").font(DS.Typography.title)
            killButtons
            Grid(alignment: .leading, horizontalSpacing: DS.Spacing.m, verticalSpacing: DS.Spacing.xs) {
                fact(String(localized: "Energy"), samples.reduce(0) { $0 + $1.energyImpact }.formatted(.number.precision(.fractionLength(0))))
                fact(String(localized: "% CPU"), (samples.reduce(0) { $0 + $1.cpuFraction } * 100).formatted(.number.precision(.fractionLength(1))))
                fact(String(localized: "Memory (footprint)"), samples.reduce(0) { $0 &+ $1.physFootprintBytes }.formatted(.byteCount(style: .memory)))
            }
            ForEach(samples) { sample in
                HStack {
                    Text(store.identities.identity(for: sample).name).lineLimit(1)
                    Spacer()
                    Text(String(sample.pid)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(DS.Typography.secondary)
            }
        }
    }

    private var killButtons: some View {
        HStack {
            Button(String(localized: "Terminate")) { model.requestTerminate(force: false) }
            Button(String(localized: "Force Quit"), role: .destructive) { model.requestTerminate(force: true) }
                .disabled(!model.canEscalateSelection())
                .help(String(localized: "Available 3 s after Terminate if the process is still running."))
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit().textSelection(.enabled)
        }
        .font(DS.Typography.secondary)
    }
}
