import LakhasKit
import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Account forms (ADR-027 §1–2). Passwords are stretched on the phone; only a derived key is sent.

/// Busy + error state shared by the forms. While busy, a progress row explains the wait
/// (600,000 PBKDF2 rounds take a moment). A class, so the busy row shows during the await.
@MainActor
@Observable
private final class FormStatus {
    var busy = false
    var error: Error?

    func run(_ work: () async throws -> Void) async -> Bool {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await work()
            return true
        } catch {
            self.error = error
            return false
        }
    }
}

private struct StatusRows: View {
    let status: FormStatus

    var body: some View {
        if status.busy {
            HStack(spacing: Theme.Space.sm) {
                ProgressView()
                Text("account.working").font(.footnote).foregroundStyle(Theme.Palette.muted)
            }
            .accessibilityIdentifier("ax.account.working")
        }
        if let error = status.error {
            Label(AccountErrorText.key(for: error), systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.accent)
                .accessibilityIdentifier("ax.account.error")
        }
    }
}

private struct EmailField: View {
    @Binding var text: String

    var body: some View {
        TextField("account.email", text: $text)
            .textContentType(ProcessInfo.processInfo.arguments.contains("-uiTesting") ? nil : .username)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityIdentifier("ax.account.emailField")
    }
}

private struct PasswordField: View {
    let titleKey: LocalizedStringKey
    @Binding var text: String
    var isNew = false
    let identifier: String

    /// UI tests type into the field; password AutoFill on the Simulator swallows typed text.
    private static let uiTesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    var body: some View {
        SecureField(titleKey, text: $text)
            .textContentType(Self.uiTesting ? nil : (isNew ? .newPassword : .password))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier(identifier)
    }
}

/// New password + confirmation, with the rules spelled out.
private struct NewPasswordFields: View {
    @Binding var password: String
    @Binding var confirm: String

    static func isValid(_ password: String, _ confirm: String) -> Bool {
        password.count >= AccountKeys.minimumPasswordLength && password == confirm
    }

    var body: some View {
        PasswordField(titleKey: "account.newPassword", text: $password, isNew: true, identifier: "ax.account.password")
        PasswordField(titleKey: "account.confirmPassword", text: $confirm, isNew: true, identifier: "ax.account.confirm")
        if !password.isEmpty, password.count < AccountKeys.minimumPasswordLength {
            Text("account.password.short \(AppFormat.current.number(AccountKeys.minimumPasswordLength))")
                .font(.footnote).foregroundStyle(Theme.Palette.warning)
        } else if !confirm.isEmpty, password != confirm {
            Text("account.password.mismatch").font(.footnote).foregroundStyle(Theme.Palette.warning)
        }
    }
}

// MARK: Recovery code (shown once)

/// The one-time recovery code with Copy and a required "I saved it" before Done.
struct RecoveryCodeCard: View {
    let code: RecoveryCode
    let onDone: () -> Void
    @State private var saved = false
    @State private var copied = false

    var body: some View {
        Section {
            Text(verbatim: code.formatted)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .environment(\.layoutDirection, .leftToRight)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding(.vertical, Theme.Space.sm)
                .accessibilityIdentifier("ax.account.recoveryCode")
            Button {
                // Local only and gone after 2 minutes: the code shouldn't linger on the clipboard.
                UIPasteboard.general.setItems([[UTType.plainText.identifier: code.formatted]],
                                              options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)])
                copied = true
            } label: {
                Label(copied ? "account.code.copied" : "account.code.copy", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
        } header: {
            Text("account.code.title")
        } footer: {
            Text("account.code.footer")
        }
        Section {
            Label("account.code.warning", systemImage: "exclamationmark.shield")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.Palette.accent)
            Toggle("account.code.saved", isOn: $saved)
                .accessibilityIdentifier("ax.account.savedToggle")
            PrimaryButton(titleKey: "common.done", isEnabled: saved, action: onDone)
                .accessibilityIdentifier("ax.account.done")
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
        }
    }
}

// MARK: Sign up

struct SignUpView: View {
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var invite = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var status = FormStatus()
    @State private var code: RecoveryCode?

    private var canSubmit: Bool {
        !status.busy && invite.trimmingCharacters(in: .whitespaces).count >= 4 && email.contains("@")
            && NewPasswordFields.isValid(password, confirm)
    }

    var body: some View {
        Form {
            if let code {
                RecoveryCodeCard(code: code) { dismiss() }
            } else {
                Section {
                    TextField("account.invite", text: $invite)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityIdentifier("ax.account.invite")
                    EmailField(text: $email)
                    NewPasswordFields(password: $password, confirm: $confirm)
                } footer: {
                    Text("account.signUp.footer")
                }
                Section {
                    PrimaryButton(titleKey: "account.signUp", isEnabled: canSubmit) {
                        Task {
                            _ = await status.run {
                                code = try await account.signUp(inviteCode: invite, email: email, password: password)
                            }
                        }
                    }
                    .accessibilityIdentifier("ax.account.submit")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    StatusRows(status: status)
                } footer: {
                    Link(destination: ServerConfig.privacyURL(language: AppFormat.current.language)) {
                        Text("account.privacy")
                    }
                }
            }
        }
        .disabled(status.busy)
        .navigationTitle("account.signUp")
        .navigationBarBackButtonHidden(code != nil)
    }
}

// MARK: Sign in

struct SignInView: View {
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var status = FormStatus()

    var body: some View {
        Form {
            Section {
                EmailField(text: $email)
                PasswordField(titleKey: "account.password", text: $password, identifier: "ax.account.password")
            }
            Section {
                PrimaryButton(titleKey: "account.signIn", isEnabled: !status.busy && email.contains("@") && !password.isEmpty) {
                    Task {
                        if await status.run({ try await account.signIn(email: email, password: password) }) { dismiss() }
                    }
                }
                .accessibilityIdentifier("ax.account.submit")
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                StatusRows(status: status)
            } footer: {
                Text("account.signIn.footer")
            }
        }
        .disabled(status.busy)
        .navigationTitle("account.signIn")
    }
}

// MARK: Reset with the recovery code

struct ResetPasswordView: View {
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var codeText = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var status = FormStatus()

    private var code: RecoveryCode? { RecoveryCode(typed: codeText) }

    var body: some View {
        Form {
            Section {
                EmailField(text: $email)
                TextField("account.code.field", text: $codeText, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityIdentifier("ax.account.codeField")
                if !codeText.isEmpty, code == nil {
                    Text("account.code.invalid").font(.footnote).foregroundStyle(Theme.Palette.warning)
                }
            } footer: {
                Text("account.reset.footer")
            }
            Section {
                NewPasswordFields(password: $password, confirm: $confirm)
            }
            Section {
                PrimaryButton(titleKey: "account.reset.submit",
                              isEnabled: !status.busy && email.contains("@") && code != nil
                                && NewPasswordFields.isValid(password, confirm)) {
                    guard let code else { return }
                    Task {
                        if await status.run({ try await account.resetPassword(email: email, code: code, newPassword: password) }) {
                            dismiss()
                        }
                    }
                }
                .accessibilityIdentifier("ax.account.submit")
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                StatusRows(status: status)
            } footer: {
                Text("account.code.warning")
            }
        }
        .disabled(status.busy)
        .navigationTitle("account.reset")
    }
}

// MARK: Signed in: password and recovery code

struct ChangePasswordView: View {
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var status = FormStatus()

    var body: some View {
        Form {
            Section {
                PasswordField(titleKey: "account.currentPassword", text: $current, identifier: "ax.account.current")
            }
            Section {
                NewPasswordFields(password: $password, confirm: $confirm)
            } footer: {
                Text("account.changePassword.footer")
            }
            Section {
                PrimaryButton(titleKey: "account.changePassword",
                              isEnabled: !status.busy && !current.isEmpty && NewPasswordFields.isValid(password, confirm)) {
                    Task {
                        if await status.run({ try await account.changePassword(current: current, new: password) }) { dismiss() }
                    }
                }
                .accessibilityIdentifier("ax.account.submit")
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                StatusRows(status: status)
            }
        }
        .disabled(status.busy)
        .navigationTitle("account.changePassword")
    }
}

struct NewRecoveryCodeView: View {
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var status = FormStatus()
    @State private var code: RecoveryCode?

    var body: some View {
        Form {
            if let code {
                RecoveryCodeCard(code: code) { dismiss() }
            } else {
                Section {
                    PasswordField(titleKey: "account.password", text: $password, identifier: "ax.account.password")
                } footer: {
                    Text("account.newCode.footer")
                }
                Section {
                    PrimaryButton(titleKey: "account.newCode", isEnabled: !status.busy && !password.isEmpty) {
                        Task { _ = await status.run { code = try await account.newRecoveryCode(password: password) } }
                    }
                    .accessibilityIdentifier("ax.account.submit")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    StatusRows(status: status)
                }
            }
        }
        .disabled(status.busy)
        .navigationTitle("account.newCode")
        .navigationBarBackButtonHidden(code != nil)
    }
}

// MARK: Delete account (App Store 5.1.1(v))

struct DeleteAccountView: View {
    enum Method: Hashable {
        case password, recoveryCode
    }

    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var method = Method.password
    @State private var secret = ""
    @State private var understood = false
    @State private var status = FormStatus()

    private var proof: AccountService.DeletionProof? {
        switch method {
        case .password: secret.isEmpty ? nil : .password(secret)
        case .recoveryCode: RecoveryCode(typed: secret).map { .recoveryCode($0) }
        }
    }

    var body: some View {
        Form {
            Section {
                Label("account.delete.what", systemImage: "trash")
                Label("account.delete.local", systemImage: "iphone")
                Label("account.delete.final", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.Palette.accent)
            }
            .font(.callout)
            Section {
                Picker("account.delete.method", selection: $method) {
                    Text("account.password").tag(Method.password)
                    Text("account.code.field").tag(Method.recoveryCode)
                }
                .pickerStyle(.segmented)
                .onChange(of: method) { secret = "" }
                if method == .password {
                    PasswordField(titleKey: "account.password", text: $secret, identifier: "ax.account.password")
                } else {
                    TextField("account.code.field", text: $secret)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityIdentifier("ax.account.codeField")
                }
                Toggle("account.delete.understood", isOn: $understood)
                    .accessibilityIdentifier("ax.account.understood")
            }
            Section {
                Button(role: .destructive) {
                    guard let proof else { return }
                    Task {
                        if await status.run({ try await account.deleteAccount(proof: proof) }) { dismiss() }
                    }
                } label: {
                    Text("account.delete.confirm").frame(maxWidth: .infinity).font(.headline)
                }
                .disabled(status.busy || !understood || proof == nil)
                .accessibilityIdentifier("ax.account.deleteConfirm")
                StatusRows(status: status)
            }
        }
        .disabled(status.busy)
        .navigationTitle("account.delete")
    }
}
