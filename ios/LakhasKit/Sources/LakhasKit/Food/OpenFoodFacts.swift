import Foundation

public enum ProductLookupError: Error, Equatable, Sendable {
    case invalidBarcode
    case network
    /// Open Food Facts answered with a server error or a rate limit.
    case unavailable
}

/// Barcode lookup on Open Food Facts, called directly from the phone with no key
/// (PROJECT_PROMPT.md §4.3 C). Data is © Open Food Facts contributors, ODbL.
public struct OpenFoodFactsClient: Sendable {
    public static let baseURL = URL(string: "https://world.openfoodfacts.org")
    public static let attributionURL = URL(string: "https://world.openfoodfacts.org")
    public static let licenseURL = URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")
    /// Open Food Facts asks apps to identify themselves.
    static let userAgent = "Lakhas/0.1 (iOS; personal app)"
    static let fields = "code,product_name,product_name_ar,product_name_en,generic_name,brands,serving_quantity,nutriments"

    /// UI tests only (`-uiTesting`): lookups are answered from this table, never the network.
    public nonisolated(unsafe) static var uiTestingProducts: [String: ProductInfo]?

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    static func productURL(barcode: String) -> URL? {
        guard var components = baseURL.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else { return nil }
        components.path = "/api/v2/product/\(barcode)"
        components.queryItems = [URLQueryItem(name: "fields", value: fields)]
        return components.url
    }

    /// nil when Open Food Facts doesn't know the barcode. A product with no usable nutrition
    /// values comes back with `per100 == nil`.
    public func product(barcode: String) async throws -> ProductInfo? {
        if let stub = Self.uiTestingProducts { return stub[barcode] }
        guard let url = Self.productURL(barcode: barcode) else { throw ProductLookupError.invalidBarcode }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ProductLookupError.network
        }
        guard let http = response as? HTTPURLResponse else { throw ProductLookupError.network }
        switch http.statusCode {
        case 200..<300: return Self.parse(data, barcode: barcode)
        case 404: return nil
        default: throw ProductLookupError.unavailable
        }
    }

    /// Parses a v2 product response. Numbers may arrive as JSON numbers or strings.
    static func parse(_ data: Data, barcode: String) -> ProductInfo? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              number(root["status"]) == 1,
              let product = root["product"] as? [String: Any] else { return nil }
        let generic = text(product["product_name"]) ?? text(product["generic_name"])
        let brand = text(product["brands"]).map { $0.split(separator: ",").first.map(String.init) ?? $0 }?
            .trimmingCharacters(in: .whitespaces)
        let fallbackName = generic ?? brand ?? barcode
        let serving = number(product["serving_quantity"]).flatMap { (1...2000).contains($0) ? $0 : nil }
        return ProductInfo(
            barcode: barcode,
            nameAr: text(product["product_name_ar"]) ?? fallbackName,
            nameEn: text(product["product_name_en"]) ?? fallbackName,
            brand: brand?.isEmpty == false ? brand : nil,
            servingGrams: serving,
            per100: per100(product["nutriments"] as? [String: Any] ?? [:]),
            source: .openFoodFacts
        )
    }

    /// kcal from `energy-kcal_100g`, else kJ ÷ 4.184, else 4/4/9 from the macros. nil when the
    /// values are missing or implausible.
    static func per100(_ nutriments: [String: Any]) -> Macros? {
        let protein = number(nutriments["proteins_100g"])
        let carbs = number(nutriments["carbohydrates_100g"])
        let fat = number(nutriments["fat_100g"])
        let kcal = number(nutriments["energy-kcal_100g"])
            ?? number(nutriments["energy_100g"]).map { ($0 / 4.184).rounded() }
            ?? {
                guard let protein, let carbs, let fat else { return nil }
                return 4 * protein + 4 * carbs + 9 * fat
            }()
        guard let kcal, kcal > 0 || [protein, carbs, fat].contains(where: { $0 != nil }) else { return nil }
        let macros = Macros(kcal: kcal, protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0)
        return ProductInfo.isPlausible(macros) ? macros : nil
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }
}
