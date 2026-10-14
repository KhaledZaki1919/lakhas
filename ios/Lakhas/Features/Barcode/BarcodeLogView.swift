import LakhasKit
import SwiftData
import SwiftUI

/// Barcode (PROJECT_PROMPT.md §4.3 C, no key for lookup): scan or type a code → local products,
/// then Open Food Facts → pick an amount → review. Unknown products are added from two label
/// photos (needs a key) or typed in, and stay on this device.
struct BarcodeLogView: View {
    let request: LogRequest
    let onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @State private var code = ""
    @State private var state: LookupState = .idle
    @State private var grams: Double = 100
    @State private var form: ProductFormBox?
    @State private var review: DraftBox?
    @State private var scans = 0
    @FocusState private var codeFocused: Bool

    private let format = AppFormat.current

    enum LookupState: Equatable {
        case idle
        case searching
        case found(ProductInfo)
        /// Unknown, or known to Open Food Facts without nutrition values (`hint` has its name).
        case missing(barcode: String, hint: ProductInfo?)
        case failed(ProductLookupError)
    }

    var body: some View {
        Form {
            if case .found(let product) = state {
                productSections(product)
            } else {
                scanSections
            }
        }
        .navigationTitle("log.barcode")
        .navigationDestination(item: $form) { box in
            ProductFormView(barcode: box.barcode, initial: box.initial) { saved in
                grams = saved.servingGrams ?? 100
                state = .found(saved)
                form = nil
            }
        }
        .navigationDestination(item: $review) { box in
            ReviewView(request: request, source: .barcode, outcome: nil, items: box.items, onSaved: onSaved)
        }
        .sensoryFeedback(.selection, trigger: scans)
    }

    // MARK: Scan

    @ViewBuilder private var scanSections: some View {
        Section {
            if BarcodeScanner.isAvailable {
                BarcodeScanner { scanned in
                    scans += 1
                    code = scanned
                    lookup(scanned)
                }
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
                .listRowInsets(EdgeInsets())
                .accessibilityLabel(Text("barcode.scan.hint"))
            } else {
                Label("barcode.scan.unavailable", systemImage: "camera.metering.unknown")
                    .foregroundStyle(Theme.Palette.muted)
            }
        } footer: {
            if BarcodeScanner.isAvailable { Text("barcode.scan.hint") }
        }
        Section {
            HStack {
                TextField("barcode.code", text: $code)
                    .keyboardType(.numberPad)
                    .focused($codeFocused)
                    .accessibilityIdentifier("ax.barcode.code")
                Button("barcode.lookup") { lookup(code) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Palette.primary)
                    .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || state == .searching)
                    .accessibilityIdentifier("ax.barcode.lookup")
            }
        } header: {
            Text("barcode.code.header")
        }
        statusSection
        Section {
            Text("barcode.off.attribution").font(.footnote).foregroundStyle(Theme.Palette.muted)
        }
    }

    @ViewBuilder private var statusSection: some View {
        switch state {
        case .idle, .found:
            EmptyView()
        case .searching:
            Section {
                HStack(spacing: Theme.Space.sm) {
                    ProgressView()
                    Text("barcode.searching")
                }
            }
        case .missing(let barcode, let hint):
            Section {
                Label(hint == nil ? LocalizedStringKey("barcode.notFound") : LocalizedStringKey("barcode.incomplete"),
                      systemImage: "questionmark.circle")
                    .accessibilityIdentifier("ax.barcode.missing")
                Button {
                    form = ProductFormBox(barcode: barcode, initial: hint)
                } label: {
                    Label("barcode.addProduct", systemImage: "text.viewfinder")
                }
                .accessibilityIdentifier("ax.barcode.addProduct")
            } footer: {
                Text("barcode.addProduct.footer")
            }
        case .failed(let error):
            Section {
                Text(error.messageKey).foregroundStyle(Theme.Palette.accent)
                if error != .invalidBarcode {
                    Button("barcode.retry") { lookup(code) }
                }
            }
        }
    }

    // MARK: Product

    @ViewBuilder private func productSections(_ product: ProductInfo) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(verbatim: product.name(language: format.language))
                    .font(.headline)
                    .accessibilityIdentifier("ax.barcode.product")
                if let brand = product.brand {
                    Text(verbatim: brand).font(.subheadline).foregroundStyle(Theme.Palette.muted)
                }
                HStack(spacing: Theme.Space.xs) {
                    Text(product.sourceKey)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.Palette.halo, in: Capsule())
                    Text(verbatim: product.barcode).font(.caption.monospacedDigit()).foregroundStyle(Theme.Palette.muted)
                }
            }
        }
        if let per100 = product.per100 {
            Section {
                valueRow("barcode.energy", per100.kcal, unitKey: "unit.kcal")
                valueRow("macro.protein", per100.protein, unitKey: "unit.g")
                valueRow("macro.carbs", per100.carbs, unitKey: "unit.g")
                valueRow("macro.fat", per100.fat, unitKey: "unit.g")
            } header: {
                Text("barcode.per100")
            }
            portionSection(product, per100: per100)
        }
        Section {
            Button {
                form = ProductFormBox(barcode: product.barcode, initial: product)
            } label: {
                Label("barcode.edit", systemImage: "pencil")
            }
            .accessibilityIdentifier("ax.barcode.edit")
            Button {
                code = ""
                state = .idle
            } label: {
                Label("barcode.scanAnother", systemImage: "barcode.viewfinder")
            }
        } footer: {
            if product.source == .openFoodFacts { attribution }
        }
    }

    private func portionSection(_ product: ProductInfo, per100: Macros) -> some View {
        Section {
            if let serving = product.servingGrams {
                portionButton(String(localized: "barcode.portion.serving \(format.number(serving, fractionDigits: 1))"), grams: serving)
                    .accessibilityIdentifier("ax.barcode.serving")
            }
            portionButton(String(localized: "barcode.portion.100"), grams: 100)
            HStack {
                TextField("unit.g", value: $grams, format: .number.precision(.fractionLength(0)).locale(format.locale))
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("ax.barcode.grams")
                Text("unit.g").foregroundStyle(Theme.Palette.muted)
                Spacer()
                Text(verbatim: "\(format.number(Int((per100.kcal * grams / 100).rounded()))) \(String(localized: "unit.kcal"))")
                    .font(.headline.monospacedDigit())
            }
            Button {
                add(product)
            } label: {
                Label("barcode.add", systemImage: "plus.circle.fill").font(.headline)
            }
            .disabled(grams <= 0)
            .accessibilityIdentifier("ax.barcode.add")
        } header: {
            Text("barcode.portion")
        }
    }

    private func portionButton(_ title: String, grams value: Double) -> some View {
        Button {
            grams = value
        } label: {
            HStack {
                Text(verbatim: title).foregroundStyle(Theme.Palette.ink)
                Spacer()
                if grams == value { Image(systemName: "checkmark").foregroundStyle(Theme.Palette.primary) }
            }
        }
    }

    private func valueRow(_ key: LocalizedStringKey, _ value: Double, unitKey: LocalizedStringKey) -> some View {
        LabeledContent {
            HStack(spacing: 2) {
                Text(verbatim: format.number(value, fractionDigits: 1)).monospacedDigit()
                Text(unitKey)
            }
        } label: {
            Text(key)
        }
    }

    private var attribution: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text("barcode.off.attribution")
            if let url = OpenFoodFactsClient.attributionURL {
                Link(destination: url) { Text("barcode.off.link") }
            }
        }
    }

    // MARK: Actions

    private func lookup(_ raw: String) {
        codeFocused = false
        guard let barcode = Barcode.normalize(raw) else {
            state = .failed(.invalidBarcode)
            return
        }
        state = .searching
        Task {
            do {
                switch try await ProductService(context: context).lookup(barcode) {
                case .saved(let product), .openFoodFacts(let product):
                    grams = product.servingGrams ?? 100
                    state = .found(product)
                case .incomplete(let partial):
                    state = .missing(barcode: barcode, hint: partial)
                case .notFound:
                    state = .missing(barcode: barcode, hint: nil)
                }
            } catch let error as ProductLookupError {
                state = .failed(error)
            } catch {
                state = .failed(.network)
            }
        }
    }

    /// Logging a product keeps it in the local library (Open Food Facts results included), so
    /// the next scan works offline.
    private func add(_ product: ProductInfo) {
        ProductService(context: context).save(product)
        review = DraftBox(items: [product.draftItem(grams: grams.rounded())])
    }
}

struct ProductFormBox: Hashable {
    let id = UUID()
    let barcode: String
    let initial: ProductInfo?

    static func == (lhs: ProductFormBox, rhs: ProductFormBox) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct DraftBox: Hashable {
    let id = UUID()
    let items: [DraftItem]

    static func == (lhs: DraftBox, rhs: DraftBox) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension ProductInfo {
    var sourceKey: LocalizedStringKey {
        if isSaved { return "barcode.source.saved" }
        switch source {
        case .openFoodFacts: return "barcode.source.off"
        case .label: return "barcode.source.label"
        case .manual: return "barcode.source.manual"
        }
    }
}

extension ProductLookupError {
    var messageKey: LocalizedStringKey {
        switch self {
        case .invalidBarcode: "barcode.error.invalid"
        case .network: "barcode.error.network"
        case .unavailable: "barcode.error.unavailable"
        }
    }
}
