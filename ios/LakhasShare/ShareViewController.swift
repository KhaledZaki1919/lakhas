import LakhasKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Receives a recipe link from TikTok/Instagram/YouTube. Extensions never call the API:
/// with an App Group the link is queued for the app; without one it goes to the clipboard
/// (docs/sideloading.md §2). Image shares arrive in Phase 6.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        Task { @MainActor in
            let outcome = await handleSharedItems()
            showResult(outcome)
        }
    }

    private func handleSharedItems() async -> ShareOutcome {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        guard let url = await firstURL(in: providers) else { return .unsupported }

        let location = AppGroupResolver.resolve()
        if location.isShared, (try? PendingImportQueue(location: location).enqueue(url: url)) != nil {
            return .queued
        }
        UIPasteboard.general.url = url
        return .copied
    }

    private func firstURL(in providers: [NSItemProvider]) async -> URL? {
        let type = UTType.url.identifier
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type) }) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                continuation.resume(returning: item as? URL)
            }
        }
    }

    private func showResult(_ outcome: ShareOutcome) {
        let host = UIHostingController(rootView: ShareResultView(outcome: outcome) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

enum ShareOutcome {
    case queued, copied, unsupported

    var messageKey: LocalizedStringKey {
        switch self {
        case .queued: "share.queued"
        case .copied: "share.copied"
        case .unsupported: "share.unsupported"
        }
    }

    var symbol: String {
        switch self {
        case .queued: "checkmark.circle.fill"
        case .copied: "doc.on.clipboard.fill"
        case .unsupported: "link.badge.plus"
        }
    }
}

struct ShareResultView: View {
    let outcome: ShareOutcome
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Image(systemName: outcome.symbol)
                .font(.system(size: 44))
                .foregroundStyle(outcome == .unsupported ? Theme.Palette.warning : Theme.Palette.primary)
                .accessibilityHidden(true)
            Text(outcome.messageKey)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Palette.ink)
            Button(action: onDone) {
                Text("common.done")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(Theme.Palette.primary)
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.bg)
    }
}
