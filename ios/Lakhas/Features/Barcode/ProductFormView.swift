import LakhasKit
import SwiftData
import SwiftUI

/// Adds or edits a product on this device. With a key, two label photos (nutrition table +
/// front) are read by the user's AI provider to fill the fields; the user checks them and saves.
/// Without a key the same fields are typed in.
struct ProductFormView: View {
    let barcode: String
    let onSaved: (ProductInfo) -> Void

    @Environment(\.modelContext) private var context
    @State private var nutritionPhoto: Data?
    @State private var frontPhoto: Data?
    @State private var nameAr: String
    @State private var nameEn: String
    @State private var brand: String
    @State private var servingGrams: Double?
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var source: ProductSource
    @State private var isReading = false
    @State private var error: AIError?
    @State private var labelNotes: String?
    @State private var costNote: String?
    @State private var unreadable = false
    @State private var implausible = false
    @State private var hasKey = LogSheet.keyAvailable()

    private let format = AppFormat.current
    private let uiTesting = ProcessInfo.processInfo.arguments.contains("-uiTestingStubAI")

    init(barcode: String, initial: ProductInfo?, onSaved: @escaping (ProductInfo) -> Void) {
        self.barcode = barcode
        self.onSaved = onSaved
        _nameAr = State(initialValue: initial?.nameAr ?? "")
        _nameEn = State(initialValue: initial?.nameEn ?? "")
        _brand = State(initialValue: initial?.brand ?? "")
        _servingGrams = State(initialValue: initial?.servingGrams)
        _kcal = State(initialValue: initial?.per100?.kcal)
        _protein = State(initialValue: initial?.per100?.protein)
        _carbs = State(initialValue: initial?.per100?.carbs)
        _fat = State(initialValue: initial?.per100?.fat)
        // Values the user edits count as their own; label values stay "from the label".
        _source = State(initialValue: initial?.source == .label ? .label : .manual)
    }

    private var hasName: Bool {
        !nameAr.trimmingCharacters(in: .whitespaces).isEmpty || !nameEn.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            labelSection
            Section {
                TextField("product.nameAr", text: $nameAr)
                    .accessibilityIdentifier("ax.product.nameAr")
                TextField("product.nameEn", text: $nameEn)
                    .accessibilityIdentifier("ax.product.nameEn")
                TextField("product.brand", text: $brand)
            } header: {
                Text("product.details")
            }
            Section {
                numberField("barcode.energy", value: $kcal, unitKey: "unit.kcal", identifier: "ax.product.kcal")
                numberField("macro.protein", value: $protein, unitKey: "unit.g", identifier: "ax.product.protein")
                numberField("macro.carbs", value: $carbs, unitKey: "unit.g", identifier: "ax.product.carbs")
                numberField("macro.fat", value: $fat, unitKey: "unit.g", identifier: "ax.product.fat")
            } header: {
                Text("product.per100")
            } footer: {
                if implausible {
                    Text("product.invalid").foregroundStyle(Theme.Palette.accent)
                } else {
                    Text("product.per100.footer")
                }
            }
            Section {
                numberField("product.serving", value: $servingGrams, unitKey: "unit.g", identifier: "ax.product.serving")
            } footer: {
                Text(verbatim: "\(String(localized: "product.barcode")) \(barcode)")
            }
        }
        .navigationTitle("product.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("common.save", action: save)
                    .disabled(!hasName || kcal == nil || isReading)
                    .accessibilityIdentifier("ax.product.save")
            }
        }
        .overlay { if isReading { AnalyzingOverlay() } }
        .onAppear { hasKey = LogSheet.keyAvailable() }
    }

    @ViewBuilder private var labelSection: some View {
        Section {
            PhotoSlot(titleKey: "product.label.nutrition", data: $nutritionPhoto)
            PhotoSlot(titleKey: "product.label.front", data: $frontPhoto)
            if uiTesting {
                Button("photo.sample") {
                    nutritionPhoto = PhotoLogView.samplePhoto()
                    frontPhoto = PhotoLogView.samplePhoto()
                }
                .accessibilityIdentifier("ax.product.sample")
            }
            if hasKey {
                Button {
                    Task { await readLabel() }
                } label: {
                    Label("product.read", systemImage: "text.viewfinder").font(.headline)
                }
                .disabled(nutritionPhoto == nil || frontPhoto == nil || isReading)
                .accessibilityIdentifier("ax.product.read")
            } else {
                NavigationLink {
                    NoKeyView()
                } label: {
                    Label("product.read.needsKey", systemImage: "key.horizontal")
                }
            }
            if let error {
                AIErrorView(error: error)
            }
            if unreadable {
                Text("product.label.unreadable").font(.footnote).foregroundStyle(Theme.Palette.accent)
            }
            if let labelNotes, !labelNotes.isEmpty {
                Label(labelNotes, systemImage: "info.circle").font(.footnote)
            }
            if let costNote {
                Text(verbatim: costNote).font(.footnote).foregroundStyle(Theme.Palette.muted)
            }
        } header: {
            Text("product.label.title")
        } footer: {
            Text("product.label.footer")
        }
    }

    private func numberField(_ key: LocalizedStringKey, value: Binding<Double?>, unitKey: LocalizedStringKey,
                             identifier: String) -> some View {
        HStack {
            Text(key)
            Spacer()
            TextField(key, value: value, format: .number.locale(format.locale))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
                .accessibilityIdentifier(identifier)
            Text(unitKey).foregroundStyle(Theme.Palette.muted)
        }
    }

    private func readLabel() async {
        guard let nutritionPhoto, let frontPhoto,
              let nutrition = ImageProcessor.prepare(nutritionPhoto), let front = ImageProcessor.prepare(frontPhoto) else { return }
        isReading = true
        error = nil
        unreadable = false
        defer { isReading = false }
        do {
            let outcome = try await ProductService.readLabel(
                nutrition: nutrition, front: front, barcode: barcode, language: format.language,
                service: AIService(context: context)
            )
            labelNotes = outcome.notes
            costNote = ReviewView.costText(fromCache: outcome.fromCache, cost: outcome.estimatedCost, model: outcome.model)
            guard let info = outcome.info else {
                unreadable = true
                return
            }
            nameAr = info.nameAr
            nameEn = info.nameEn
            brand = info.brand ?? ""
            servingGrams = info.servingGrams
            kcal = info.per100?.kcal
            protein = info.per100?.protein
            carbs = info.per100?.carbs
            fat = info.per100?.fat
            source = .label
            implausible = false
        } catch let aiError as AIError {
            error = aiError
        } catch {
            self.error = .network
        }
    }

    private func save() {
        let per100 = Macros(kcal: kcal ?? 0, protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0)
        guard ProductInfo.isPlausible(per100), servingGrams.map({ (1...2000).contains($0) }) ?? true else {
            implausible = true
            return
        }
        let ar = nameAr.trimmingCharacters(in: .whitespaces)
        let en = nameEn.trimmingCharacters(in: .whitespaces)
        let trimmedBrand = brand.trimmingCharacters(in: .whitespaces)
        var info = ProductInfo(barcode: barcode, nameAr: ar.isEmpty ? en : ar, nameEn: en.isEmpty ? ar : en,
                               brand: trimmedBrand.isEmpty ? nil : trimmedBrand, servingGrams: servingGrams,
                               per100: per100, source: source)
        ProductService(context: context).save(info, photo: frontPhoto)
        info.isSaved = true
        onSaved(info)
    }
}
