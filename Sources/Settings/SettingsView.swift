import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Picker(String(localized: "Menu bar icon shows"), selection: $settings.iconContent) {
                ForEach(IconContent.allCases, id: \.self) { Text($0.localizedName).tag($0) }
            }
            Toggle(String(localized: "Launch at login"), isOn: $settings.launchAtLogin)
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize()
    }
}
