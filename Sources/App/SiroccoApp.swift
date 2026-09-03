import SwiftUI

@main
struct SiroccoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsView().environment(delegate.settings)
        }
    }
}
