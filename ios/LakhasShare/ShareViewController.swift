import LakhasKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Receives a recipe link from TikTok/Instagram/YouTube (a URL, or text that contains one).
/// Extensions never call the network: the link is copied to the clipboard with a marker (free
/// Apple IDs often have no App Group) and, when an App Group works, also queued. The app offers
/// "Import the shared link?" when it opens (docs/sideloading.md §2).
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
        guard let url = await firstRecipeLink(in: providers) else { return .unsupported }

        UIPasteboard.general.setItems(
            [[UTType.url.identifier: url, PendingImportQueue.clipboardMarkerType: Data("1".utf8)]],
            options: [.expirationDate: Date().addingTimeInterval(PendingImportQueue.clipboardLifetime)]
        )
        let location = AppGroupResolver.resolve()
        if location.isShared, (try? PendingImportQueue(location: location).enqueue(url: url)) != nil {
            return .queued
        }
        return .copied
    }

    /// The first TikTok / Instagram / YouTube link among the shared URLs and texts.
    private func firstRecipeLink(in providers: [NSItemProvider]) async -> URL? {
        for type in [UTType.url.identifier, UTType.plainText.identifier] {
            for provider in providers where provider.hasItemConformingToTypeIdentifier(type) {
                let text = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                    provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                        let text = (item as? URL)?.absoluteString ?? (item as? String)
                            ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
                        continuation.resume(returning: text)
                    }
                }
                if let text, let url = RecipeLink.parse(text) { return RecipeLink.canonical(url) }
            }
        }
        return nil
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
