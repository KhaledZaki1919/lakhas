import LakhasKit
import SwiftUI
import UIKit

/// An AI error: the friendly message, the provider's own words (HTTP status + message from the
/// last request), and a link to the full diagnostics.
struct AIErrorView: View {
    let error: AIError

    @State private var diagnostic = AIDiagnosticsStore.load()

    /// Errors raised before any request (no key, daily limit) have no request to describe.
    private var detail: String? {
        guard error != .noKey, error != .dailyLimitReached,
              let diagnostic, !diagnostic.succeeded,
              Date().timeIntervalSince(diagnostic.date) < 600 else { return nil }
        let status = diagnostic.httpStatus.map { "HTTP \($0)" }
        let parts = [status, diagnostic.message].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(error.messageKey).font(.footnote).foregroundStyle(Theme.Palette.accent)
            if let detail {
                Text(verbatim: detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.Palette.muted)
                    .lineLimit(5)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("ax.ai.error.detail")
            }
            if diagnostic != nil {
                NavigationLink {
                    AIDiagnosticsView()
                } label: {
                    Text("ai.diag.open").font(.caption.weight(.semibold))
                }
                .accessibilityIdentifier("ax.ai.error.details")
            }
        }
        .onAppear { diagnostic = AIDiagnosticsStore.load() }
        .onChange(of: error) { _, _ in diagnostic = AIDiagnosticsStore.load() }
    }
}

/// Settings → AI → "Last AI request": what the app sent and what came back, without the key.
struct AIDiagnosticsView: View {
    @State private var diagnostic = AIDiagnosticsStore.load()
    @State private var copied = 0

    private let format = AppFormat.current

    var body: some View {
        Form {
            if let diagnostic {
                summary(diagnostic)
                if let message = diagnostic.message {
                    textSection("ai.diag.message", message)
                }
                if let body = diagnostic.errorBody {
                    textSection("ai.diag.errorBody", body)
                }
                if let reply = diagnostic.replyExcerpt {
                    textSection("ai.diag.reply", reply)
                }
                Section {
                    Button {
                        UIPasteboard.general.string = diagnostic.report()
                        copied += 1
                    } label: {
                        Label("ai.diag.copy", systemImage: "doc.on.doc")
                    }
                    .accessibilityIdentifier("ax.ai.diag.copy")
                    if copied > 0 {
                        Text("ai.diag.copied").font(.footnote).foregroundStyle(Theme.Palette.success)
                    }
                } footer: {
                    Text("ai.diag.footer")
                }
            } else {
                Text("ai.diag.none").foregroundStyle(Theme.Palette.muted)
            }
        }
        .navigationTitle("ai.diag.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { diagnostic = AIDiagnosticsStore.load() }
        .sensoryFeedback(.success, trigger: copied)
    }

    private func summary(_ diagnostic: AIDiagnostic) -> some View {
        Section {
            if let step = diagnostic.failedStep {
                Label {
                    Text(step.titleKey)
                } icon: {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.Palette.accent)
                }
                .accessibilityIdentifier("ax.ai.diag.result")
                if diagnostic.attempts > 1 {
                    Text("ai.diag.afterRetry").font(.footnote).foregroundStyle(Theme.Palette.muted)
                }
            } else {
                Label {
                    Text("ai.diag.success")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.success)
                }
                .accessibilityIdentifier("ax.ai.diag.result")
            }
            row("ai.diag.date", format.longDate(diagnostic.date) + " " + diagnostic.date.formatted(date: .omitted, time: .standard))
            row("ai.diag.provider", diagnostic.provider.displayName)
            row("ai.diag.model", diagnostic.model, monospaced: true)
            row("ai.diag.feature", diagnostic.feature.rawValue, monospaced: true)
            row("ai.diag.endpoint", diagnostic.endpoint ?? "—", monospaced: true)
            row("ai.diag.status", diagnostic.httpStatus.map(String.init) ?? "—", monospaced: true)
            row("ai.diag.duration", "\(format.number(diagnostic.durationMs)) ms", monospaced: true)
            row("ai.diag.attempts", format.number(diagnostic.attempts))
        }
    }

    private func row(_ key: LocalizedStringKey, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key).font(.caption).foregroundStyle(Theme.Palette.muted)
            if monospaced {
                // IDs, URLs and numbers are Latin text.
                Text(verbatim: value)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .environment(\.layoutDirection, .leftToRight)
            } else {
                Text(verbatim: value).font(.callout)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func textSection(_ key: LocalizedStringKey, _ text: String) -> some View {
        Section {
            Text(verbatim: text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .leftToRight)   // provider text is mostly Latin
        } header: {
            Text(key)
        }
    }
}

extension AIDiagnostic.Step {
    var titleKey: LocalizedStringKey {
        switch self {
        case .network: "ai.diag.step.network"
        case .http: "ai.diag.step.http"
        case .response: "ai.diag.step.response"
        case .json: "ai.diag.step.json"
        case .validation: "ai.diag.step.validation"
        case .timeout: "ai.diag.step.timeout"
        case .cancelled: "ai.diag.step.cancelled"
        }
    }
}
