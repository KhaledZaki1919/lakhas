import LakhasKit
import SwiftData
import SwiftUI
import UIKit

/// Photo scan (needs the user's key): camera or library, optional leftover photo, then review.
struct PhotoLogView: View {
    let request: LogRequest
    let onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @State private var mealPhoto: Data?
    @State private var leftoverPhoto: Data?
    @State private var withLeftovers = false
    @State private var note = ""
    @State private var isAnalyzing = false
    @State private var error: AIError?
    @State private var result: OutcomeBox?

    private let format = AppFormat.current
    private let uiTesting = ProcessInfo.processInfo.arguments.contains("-uiTestingStubAI")

    var body: some View {
        Form {
            Section {
                PhotoSlot(titleKey: "photo.meal", data: $mealPhoto)
                if uiTesting {
                    Button("photo.sample") { mealPhoto = Self.samplePhoto() }
                        .accessibilityIdentifier("ax.photo.sample")
                }
            } footer: {
                Text("photo.privacy")
            }
            Section {
                Toggle("photo.leftovers", isOn: $withLeftovers)
                if withLeftovers {
                    PhotoSlot(titleKey: "photo.leftoverPhoto", data: $leftoverPhoto)
                }
            } footer: {
                Text("photo.leftovers.footer")
            }
            Section {
                TextField("photo.note", text: $note, axis: .vertical)
                    .lineLimit(1...3)
            }
        }
        // Pinned so it stays reachable once a photo preview fills the screen.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Space.xs) {
                if let error {
                    AIErrorView(error: error)
                }
                PrimaryButton(titleKey: "photo.analyze",
                              isEnabled: mealPhoto != nil && !isAnalyzing && !(withLeftovers && leftoverPhoto == nil)) {
                    Task { await analyze() }
                }
                .accessibilityIdentifier("ax.photo.analyze")
            }
            .padding(Theme.Space.md)
            .background(Theme.Palette.surface)
        }
        .navigationTitle("log.photo")
        .navigationDestination(item: $result) { box in
            ReviewView(request: request, source: .photo, outcome: box.outcome, photoData: mealPhoto, onSaved: onSaved)
        }
        .overlay { if isAnalyzing { AnalyzingOverlay() } }
    }

    private func analyze() async {
        guard let mealPhoto, let meal = ImageProcessor.prepare(mealPhoto) else { return }
        let leftover = withLeftovers ? leftoverPhoto.flatMap { ImageProcessor.prepare($0) } : nil
        isAnalyzing = true
        error = nil
        defer { isAnalyzing = false }
        do {
            let outcome = try await MealAnalyzer(service: AIService(context: context))
                .analyzePhoto(meal, leftover: leftover, note: note, language: format.language)
            result = OutcomeBox(outcome: outcome)
        } catch let aiError as AIError {
            error = aiError
        } catch {
            self.error = .network
        }
    }

    /// UI tests only: a plain image standing in for a camera photo.
    static func samplePhoto() -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600))
        return renderer.jpegData(withCompressionQuality: 0.8) { context in
            UIColor.brown.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        }
    }
}

/// Free-text entry (needs the user's key): same analysis and review screen.
struct TextLogView: View {
    let request: LogRequest
    let onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @State private var text = ""
    @State private var isAnalyzing = false
    @State private var error: AIError?
    @State private var result: OutcomeBox?

    private let format = AppFormat.current

    var body: some View {
        Form {
            Section {
                TextField("textlog.placeholder", text: $text, axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityIdentifier("ax.text.input")
            } footer: {
                Text("textlog.footer")
            }
            Section {
                Button {
                    Task { await analyze() }
                } label: {
                    HStack {
                        Text("photo.analyze").font(.headline)
                        Spacer()
                        if isAnalyzing { ProgressView() }
                    }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnalyzing)
                .accessibilityIdentifier("ax.text.analyze")
                if let error {
                    AIErrorView(error: error)
                }
            }
        }
        .navigationTitle("log.text")
        .navigationDestination(item: $result) { box in
            ReviewView(request: request, source: .text, outcome: box.outcome, onSaved: onSaved)
        }
        .overlay { if isAnalyzing { AnalyzingOverlay() } }
    }

    private func analyze() async {
        isAnalyzing = true
        error = nil
        defer { isAnalyzing = false }
        do {
            let outcome = try await MealAnalyzer(service: AIService(context: context))
                .analyzeText(text, language: format.language)
            result = OutcomeBox(outcome: outcome)
        } catch let aiError as AIError {
            error = aiError
        } catch {
            self.error = .network
        }
    }
}

/// `navigationDestination(item:)` needs a Hashable value.
struct OutcomeBox: Hashable {
    let id = UUID()
    let outcome: MealAnalyzer.Outcome

    static func == (lhs: OutcomeBox, rhs: OutcomeBox) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Skeleton-style progress while the provider works (docs/design.md §4).
struct AnalyzingOverlay: View {
    var body: some View {
        VStack(spacing: Theme.Space.md) {
            ProgressView().controlSize(.large).tint(Theme.Palette.primary)
            Text("photo.analyzing").font(.headline).foregroundStyle(Theme.Palette.ink)
        }
        .padding(Theme.Space.xl)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
    }
}

/// Camera capture (UIImagePickerController); the photo is processed before use.
struct CameraView: UIViewControllerRepresentable {
    /// nil when the user cancels.
    let onCapture: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (Data?) -> Void

        init(onCapture: @escaping (Data?) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onCapture(image?.jpegData(compressionQuality: 0.9))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}
