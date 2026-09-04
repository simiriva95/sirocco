import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var newProtectedName = ""

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section(String(localized: "General")) {
                Picker(String(localized: "Menu bar icon shows"), selection: $settings.iconContent) {
                    ForEach(IconContent.allCases, id: \.self) { Text($0.localizedName).tag($0) }
                }
                Picker(String(localized: "Appearance"), selection: $settings.theme) {
                    ForEach(Theme.allCases, id: \.self) { Text($0.localizedName).tag($0) }
                }
                Toggle(String(localized: "Launch at login"), isOn: $settings.launchAtLogin)
            }
            Section(String(localized: "Sampling")) {
                Picker(String(localized: "Interval at rest"), selection: $settings.restIntervalSeconds) {
                    Text("1 s").tag(1); Text("2 s").tag(2); Text("5 s").tag(5)
                }
                Text("The popover always samples every second; the main window every 2 s; everything slows down under thermal pressure.")
                    .font(DS.Typography.secondary).foregroundStyle(.secondary)
            }
            Section(String(localized: "Thresholds")) {
                LabeledContent(String(localized: "CPU attention")) {
                    HStack {
                        Slider(value: $settings.cpuAttention, in: 0.3...0.9, step: 0.05).accessibilityLabel(String(localized: "CPU attention"))
                        Text(Format.percent(settings.cpuAttention)).monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                LabeledContent(String(localized: "CPU critical")) {
                    HStack {
                        Slider(value: $settings.cpuCritical, in: 0.5...1, step: 0.05).accessibilityLabel(String(localized: "CPU critical"))
                        Text(Format.percent(settings.cpuCritical)).monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
            }
            Section(String(localized: "Units")) {
                Picker(String(localized: "Memory units"), selection: $settings.binaryUnits) {
                    Text("GB (1024, like Activity Monitor)").tag(true)
                    Text("GB (1000)").tag(false)
                }
            }
            Section(String(localized: "Protected processes")) {
                Text("Never terminable from Sirocco, in addition to the built-in system list (kernel_task, launchd, WindowServer, loginwindow, coreaudiod, mds*, backupd).")
                    .font(DS.Typography.secondary).foregroundStyle(.secondary)
                ForEach(settings.protectedNames, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button(role: .destructive) { settings.protectedNames.removeAll { $0 == name } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).accessibilityLabel(String(localized: "Remove \(name)"))
                    }
                }
                HStack {
                    TextField(String(localized: "Process or app name"), text: $newProtectedName).onSubmit(addProtected)
                    Button(String(localized: "Add"), action: addProtected).disabled(newProtectedName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section(String(localized: "Shortcuts")) {
                LabeledContent(String(localized: "Toggle popover anywhere"), value: "⌃⌥S")
                LabeledContent(String(localized: "Open Sirocco"), value: "⌘O")
                LabeledContent(String(localized: "Terminate / Force Quit"), value: "⌘⌫ / ⌘⌥⌫")
                LabeledContent(String(localized: "Sections"), value: "⌘1 … ⌘5")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 640)
    }

    private func addProtected() {
        let name = newProtectedName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !settings.protectedNames.contains(name) else { return }
        settings.protectedNames.append(name)
        newProtectedName = ""
    }
}
