import LakhasKit
import SwiftUI
import VisionKit

/// First-launch screen: paste or scan the device token from the admin panel (ADR-013).
struct TokenEntryView: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var isActivating = false
    @State private var error: TokenEntryError?
    @State private var isScanning = false

    private var canScan: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        ZStack {
            Theme.Palette.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    header
                    tokenField
                    actions
                    if let error {
                        Text(error.messageKey)
                            .font(.callout)
                            .foregroundStyle(Theme.Palette.accent)
                    }
                    offlineNote
                }
                .padding(Theme.Space.screenMargin)
                .padding(.top, Theme.Space.xxl)
            }
        }
        .sheet(isPresented: $isScanning) {
            QRScannerView { payload in
                isScanning = false
                text = payload
                Task { await activate() }
            }
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("common.appName")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.Palette.primary)
            Text("token.title")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text("token.subtitle")
                .font(.callout)
                .foregroundStyle(Theme.Palette.muted)
        }
    }

    private var tokenField: some View {
        TextField("token.placeholder", text: $text, axis: .vertical)
            .font(.callout.monospaced())
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .lineLimit(2...4)
            .padding(Theme.Space.sm)
            .background(Theme.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .environment(\.layoutDirection, .leftToRight)   // tokens are Latin text
            .accessibilityLabel(Text("token.placeholder"))
    }

    private var actions: some View {
        VStack(spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                PasteButton(payloadType: String.self) { strings in
                    if let first = strings.first { text = first }
                }
                .buttonBorderShape(.capsule)
                .tint(Theme.Palette.primary)
                if canScan {
                    Button {
                        isScanning = true
                    } label: {
                        Label("token.scan", systemImage: "qrcode.viewfinder")
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(Theme.Palette.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await activate() }
            } label: {
                Group {
                    if isActivating {
                        ProgressView().tint(Theme.Palette.onPrimary)
                    } else {
                        Text("token.activate").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(Theme.Palette.primary)
            .disabled(isActivating || DeviceToken(text) == nil)
        }
    }

    private var offlineNote: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(model.isServerConfigured
                 ? LocalizedStringKey("token.skipNote") : LocalizedStringKey("token.serverNotConfigured"))
                .font(.footnote)
                .foregroundStyle(Theme.Palette.muted)
            Button("token.continueOffline") { model.continueOffline() }
                .accessibilityIdentifier("ax.token.skip")
                .font(.footnote.weight(.semibold))
                .tint(Theme.Palette.primary)
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
    }

    private func activate() async {
        isActivating = true
        error = await model.activate(text)
        isActivating = false
    }
}

/// VisionKit QR scanner for the token QR code shown in the admin panel.
struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var delivered = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue,
                   DeviceToken(payload) != nil, !delivered {
                    delivered = true
                    dataScanner.stopScanning()
                    onScan(payload)
                    return
                }
            }
        }
    }
}
