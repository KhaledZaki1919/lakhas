import LakhasKit
import SwiftUI
import UIKit

/// A recipe link waiting when the app opens: queued by the share extension through the App
/// Group, or on the clipboard. Free Apple IDs often get no App Group, so the extension also
/// copies the link (docs/sideloading.md §2).
enum ImportOffer: Identifiable, Equatable {
    case queued(PendingImport)
    /// `fromShare`: the share extension's marker is on the clipboard, not just any link.
    case clipboard(fromShare: Bool)

    var id: String {
        switch self {
        case .queued(let item): item.id.uuidString
        case .clipboard(let fromShare): "clipboard-\(fromShare)"
        }
    }

    var messageKey: LocalizedStringKey {
        switch self {
        case .queued(let item): "recipes.offer.shared \(item.url.host ?? item.url.absoluteString)"
        case .clipboard(true): "recipes.offer.sharedCopied"
        case .clipboard(false): "recipes.offer.copied"
        }
    }
}

@MainActor
enum ImportOfferFinder {
    /// The clipboard change already offered (or declined), so a link is offered once.
    static let seenChangeCountKey = "recipeClipboardChangeCount"

    /// Checks without reading the clipboard's contents, so iOS shows no paste prompt.
    static func next(defaults: UserDefaults = .standard) async -> ImportOffer? {
        if let queued = PendingImportQueue(location: AppGroupResolver.resolve()).list().first {
            return .queued(queued)
        }
        let board = UIPasteboard.general
        guard board.changeCount != defaults.integer(forKey: seenChangeCountKey) else { return nil }
        if board.contains(pasteboardTypes: [PendingImportQueue.clipboardMarkerType]) { return .clipboard(fromShare: true) }
        let hasLink = await withCheckedContinuation { continuation in
            board.detectPatterns(for: [\UIPasteboard.DetectedValues.probableWebURL]) { result in
                let patterns = (try? result.get()) ?? []
                continuation.resume(returning: patterns.contains(\UIPasteboard.DetectedValues.probableWebURL))
            }
        }
        return hasLink ? .clipboard(fromShare: false) : nil
    }

    static func markClipboardSeen(defaults: UserDefaults = .standard) {
        defaults.set(UIPasteboard.general.changeCount, forKey: seenChangeCountKey)
    }

    /// Reads the clipboard after the user chose to import (iOS may ask to allow pasting).
    static func clipboardText() -> String? {
        let board = UIPasteboard.general
        guard let text = board.url?.absoluteString ?? board.string else { return nil }
        return String(text.prefix(2000))
    }

    static func remove(_ item: PendingImport) {
        PendingImportQueue(location: AppGroupResolver.resolve()).remove(item)
    }
}
