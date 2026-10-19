import LakhasKit
import SwiftUI

/// Settings → Account (ADR-027): optional. Signed out, it explains what an account is for and
/// offers sign up / sign in / reset with the recovery code. Signed in, it shows the devices,
/// the product-sharing switch, password and recovery code, sign out and delete account.
struct AccountView: View {
    @Environment(AccountModel.self) private var account
    @State private var loadError: Error?
    @State private var busy = false
    @State private var confirmSignOut = false

    private let format = AppFormat.current

    var body: some View {
        List {
            if let session = account.session {
                signedIn(session)
            } else {
                signedOut
            }
            Section {
                Link(destination: ServerConfig.privacyURL(language: format.language)) {
                    Label("account.privacy", systemImage: "hand.raised")
                }
                .accessibilityIdentifier("ax.account.privacy")
                Link(destination: ServerConfig.termsURL(language: format.language)) {
                    Label("account.terms", systemImage: "doc.text")
                }
            }
        }
        .navigationTitle("account.title")
        .task(id: account.session?.deviceId) { await load() }
        .refreshable { await load() }
    }

    // MARK: Signed out

    @ViewBuilder private var signedOut: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Label("account.signedOut.title", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.headline)
                Text("account.signedOut.body").font(.callout).foregroundStyle(Theme.Palette.muted)
            }
            .padding(.vertical, Theme.Space.xxs)
        }
        Section {
            NavigationLink {
                SignUpView()
            } label: {
                Label("account.signUp", systemImage: "person.badge.plus")
            }
            .accessibilityIdentifier("ax.account.signUp")
            NavigationLink {
                SignInView()
            } label: {
                Label("account.signIn", systemImage: "person.crop.circle")
            }
            .accessibilityIdentifier("ax.account.signIn")
            NavigationLink {
                ResetPasswordView()
            } label: {
                Label("account.reset", systemImage: "key")
            }
            .accessibilityIdentifier("ax.account.reset")
        } footer: {
            Text("account.signedOut.footer")
        }
    }

    // MARK: Signed in

    @ViewBuilder private func signedIn(_ session: StoredSession) -> some View {
        Section {
            LabeledContent("account.email") {
                Text(verbatim: session.email)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityIdentifier("ax.account.email")
            }
            if let loadError {
                Label(AccountErrorText.key(for: loadError), systemImage: "wifi.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.warning)
            }
        }

        if let info = account.info {
            Section {
                Toggle(isOn: Binding(get: { info.user.shareProducts }, set: { share in
                    Task { await run { try await account.setShareProducts(share) } }
                })) {
                    Text("account.shareProducts")
                }
                .disabled(busy)
                .accessibilityIdentifier("ax.account.shareProducts")
            } footer: {
                Text("account.shareProducts.footer")
            }

            Section {
                ForEach(info.devices.filter(\.isActive)) { device in
                    DeviceRow(device: device, format: format)
                        .swipeActions {
                            if !device.current {
                                Button("account.devices.signOut", role: .destructive) {
                                    Task { await run { try await account.signOutDevice(device) } }
                                }
                            }
                        }
                }
            } header: {
                Text("account.devices")
            } footer: {
                Text("account.devices.footer")
            }
        }

        Section {
            NavigationLink {
                ChangePasswordView()
            } label: {
                Label("account.changePassword", systemImage: "lock.rotation")
            }
            .accessibilityIdentifier("ax.account.changePassword")
            NavigationLink {
                NewRecoveryCodeView()
            } label: {
                Label("account.newCode", systemImage: "key.viewfinder")
            }
            .accessibilityIdentifier("ax.account.newCode")
        }

        Section {
            Button {
                confirmSignOut = true
            } label: {
                Label("account.signOut", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .accessibilityIdentifier("ax.account.signOut")
            .confirmationDialog("account.signOut.confirm", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("account.signOut", role: .destructive) {
                    Task { await account.signOut() }
                }
                .accessibilityIdentifier("ax.account.signOutConfirm")
            } message: {
                Text("account.signOut.message")
            }
            NavigationLink {
                DeleteAccountView()
            } label: {
                Label("account.delete", systemImage: "trash")
                    .foregroundStyle(Theme.Palette.accent)
            }
            .accessibilityIdentifier("ax.account.delete")
        }
    }

    private func load() async {
        guard account.isSignedIn else { return }
        await run { try await account.loadInfo() }
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await work()
            loadError = nil
        } catch {
            loadError = error
        }
    }
}

private struct DeviceRow: View {
    let device: AccountInfo.Device
    let format: AppFormat

    var body: some View {
        HStack {
            Image(systemName: "iphone").foregroundStyle(Theme.Palette.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: device.label).font(.callout.weight(.semibold))
                if let seen = device.lastSeenAt {
                    Text("account.devices.lastSeen \(Date(timeIntervalSince1970: Double(seen) / 1000).formatted(.relative(presentation: .named).locale(format.locale)))")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.muted)
                }
            }
            Spacer()
            if device.current {
                Text("account.devices.thisPhone")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.primary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
