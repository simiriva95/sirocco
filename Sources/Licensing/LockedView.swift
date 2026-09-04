import SwiftUI

/// Shown in place of the popover and the main window once the trial is over.
struct LockedView: View {
    @Environment(LicenseManager.self) private var license
    @State private var password = ""
    @State private var wrong = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack(spacing: DS.Spacing.s) {
                Image(systemName: "lock.fill").foregroundStyle(DS.color(.attention)).accessibilityHidden(true)
                Text("Trial expired").font(DS.Typography.title)
            }
            Text("Thanks for trying Sirocco. The 14-day trial is over; a purchase option is coming. If you own an unlock password, enter it below.")
                .font(DS.Typography.label).fixedSize(horizontal: false, vertical: true)
            HStack {
                SecureField(String(localized: "Unlock password"), text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(attempt)
                Button(String(localized: "Unlock"), action: attempt).disabled(password.isEmpty)
            }
            if wrong {
                Text("Wrong password.").font(DS.Typography.secondary).foregroundStyle(DS.color(.critical))
            }
            HStack {
                Spacer()
                Button(String(localized: "Quit")) { NSApp.terminate(nil) }.buttonStyle(.link)
            }
        }
        .padding(DS.Spacing.l)
        .frame(width: DS.Chart.popoverWidth)
    }

    private func attempt() {
        wrong = !license.unlock(password: password)
        if !wrong { password = "" }
    }
}

/// One-line trial status for the popover footer and Settings.
struct LicenseStatusText: View {
    @Environment(LicenseManager.self) private var license

    var body: some View {
        switch license.state {
        case .trial(let days): Text("Trial: \(days) days left").font(DS.Typography.secondary).foregroundStyle(days <= 3 ? DS.color(.attention) : .secondary)
        case .expired: Text("Trial expired").font(DS.Typography.secondary).foregroundStyle(DS.color(.critical))
        case .unlocked: Text("Unlocked").font(DS.Typography.secondary).foregroundStyle(.secondary)
        }
    }
}
