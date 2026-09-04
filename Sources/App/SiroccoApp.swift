import SwiftUI

@main
struct SiroccoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsView().environment(delegate.settings).environment(delegate.license)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button(String(localized: "Open Sirocco")) { delegate.showMainWindow() }.keyboardShortcut("o")
            }
            CommandGroup(after: .textEditing) {
                Button(String(localized: "Find")) { delegate.mainModel.searchFocusRequest += 1 }.keyboardShortcut("f")
            }
            CommandMenu(String(localized: "Process")) {
                Button(String(localized: "Terminate")) { delegate.mainModel.requestTerminate(force: false) }
                    .keyboardShortcut(.delete, modifiers: .command)
                Button(String(localized: "Force Quit")) { delegate.mainModel.requestTerminate(force: true) }
                    .keyboardShortcut(.delete, modifiers: [.command, .option])
                Button(String(localized: "Show Details")) { delegate.mainModel.showInspector.toggle() }
                    .keyboardShortcut("i")
            }
            CommandGroup(after: .toolbar) {
                ForEach(Array(MainTab.allCases.enumerated()), id: \.element) { index, tab in
                    Button(tab.title) { delegate.mainModel.tab = tab; delegate.pushDemand() }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
        }
    }
}
