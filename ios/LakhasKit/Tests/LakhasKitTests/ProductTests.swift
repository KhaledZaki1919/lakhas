import Foundation
import SwiftData
import Testing
@testable import LakhasKit

/// Serves Open Food Facts answers by barcode (its own statics, so it never races `StubProtocol`).
private final class OFFStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var byBarcode: [String: (status: Int, body: String)] = [:]
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OFFStub.self]
        return URLSession(configuration: config)
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let code = request.url?.pathComponents.last ?? ""
        let answer = Self.byBarcode[code] ?? (404, #"{"status":0,"status_verbose":"product not found"}"#)
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: nil, headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private let nutella = #"""
{"code":"3017620422003","status":1,"status_verbose":"product found","product":{"brands":"Nutella, Ferrero",
"product_name":"Nutella","product_name_ar":"نوتيلا","serving_quantity":"15",
"nutriments":{"energy-kcal_100g":539,"energy_100g":2252,"proteins_100g":6.3,"carbohydrates_100g":57.5,"fat_100g":30.9}}}
"""#

struct BarcodeTests {
    @Test(arguments: [
        ("3017620422003", "3017620422003"),
        ("036000291452", "0036000291452"),       // UPC-A → EAN-13
        ("03017620422003", "3017620422003"),     // GTIN-14 with a leading 0
        ("3017-6204-22003", "3017620422003"),
        (" 96385074 ", "96385074"),               // EAN-8
        ("٣٠١٧٦٢٠٤٢٢٠٠٣", "3017620422003"),      // typed with Eastern Arabic digits
    ])
    func normalizesValidCodes(raw: String, expected: String) {
        #expect(Barcode.normalize(raw) == expected)
    }

    @Test(arguments: ["3017620422004", "12345", "30176204220031", "abc3017620422003", "", "½3017620422003"])
    func rejectsInvalidCodes(raw: String) {
        #expect(Barcode.normalize(raw) == nil)
    }
}

struct OpenFoodFactsTests {
    @Test func parsesAProductWithStringNumbersAndArabicName() throws {
        let info = try #require(OpenFoodFactsClient.parse(Data(nutella.utf8), barcode: "3017620422003"))
        #expect(info.nameAr == "نوتيلا")
        #expect(info.nameEn == "Nutella")             // falls back to product_name
        #expect(info.brand == "Nutella")              // first brand only
        #expect(info.servingGrams == 15)
        #expect(info.per100 == Macros(kcal: 539, protein: 6.3, carbs: 57.5, fat: 30.9))
        #expect(info.source == .openFoodFacts)
    }

    @Test func convertsKilojoulesWhenKcalIsMissing() throws {
        let macros = try #require(OpenFoodFactsClient.per100(["energy_100g": 1000, "proteins_100g": 5, "carbohydrates_100g": 40, "fat_100g": 5]))
        #expect(macros.kcal == 239)
    }

    @Test func computesKcalFromMacrosAsALastResort() throws {
        let macros = try #require(OpenFoodFactsClient.per100(["proteins_100g": 10, "carbohydrates_100g": 20, "fat_100g": "5"]))
        #expect(macros.kcal == 165)
    }

    @Test func missingOrImplausibleValuesGiveNoMacros() {
        #expect(OpenFoodFactsClient.per100([:]) == nil)
        #expect(OpenFoodFactsClient.per100(["energy-kcal_100g": 2252, "fat_100g": 30]) == nil)   // kJ in the kcal field
        #expect(OpenFoodFactsClient.per100(["energy-kcal_100g": 400, "proteins_100g": 80, "carbohydrates_100g": 80]) == nil)
    }

    @Test func notFoundStatusParsesToNil() {
        #expect(OpenFoodFactsClient.parse(Data(#"{"status":0}"#.utf8), barcode: "1") == nil)
    }

    @Test func requestURLAsksOnlyForNeededFields() throws {
        let url = try #require(OpenFoodFactsClient.productURL(barcode: "3017620422003"))
        #expect(url.absoluteString.hasPrefix("https://world.openfoodfacts.org/api/v2/product/3017620422003?fields="))
        #expect(url.absoluteString.contains("nutriments"))
    }
}

@Suite(.serialized)
@MainActor
struct ProductServiceTests {
    private func makeService() throws -> (ProductService, ModelContext) {
        let context = ModelContext(try LakhasStore.makeContainer(inMemory: true))
        return (ProductService(context: context, client: OpenFoodFactsClient(session: OFFStub.session())), context)
    }

    @Test func looksUpOpenFoodFactsThenPrefersTheSavedProduct() async throws {
        OFFStub.byBarcode = ["3017620422003": (200, nutella)]
        OFFStub.requests = []
        let (service, _) = try makeService()

        guard case .openFoodFacts(let found) = try await service.lookup("3017620422003") else {
            Issue.record("expected an Open Food Facts product")
            return
        }
        #expect(OFFStub.requests.first?.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Lakhas/") == true)
        service.save(found)

        let again = try await service.lookup("03017620422003")
        #expect(again == .saved(ProductInfo(barcode: "3017620422003", nameAr: "نوتيلا", nameEn: "Nutella", brand: "Nutella",
                                             servingGrams: 15, per100: found.per100, source: .openFoodFacts, isSaved: true)))
        #expect(OFFStub.requests.count == 1)   // the second lookup never left the phone
    }

    @Test func unknownAndIncompleteProducts() async throws {
        OFFStub.byBarcode = ["6221000000010": (200, #"{"status":1,"product":{"product_name":"Mystery","nutriments":{}}}"#),
                             "6221000000027": (503, "")]
        let (service, _) = try makeService()
        #expect(try await service.lookup("5000159404020") == .notFound)
        guard case .incomplete(let partial) = try await service.lookup("6221000000010") else {
            Issue.record("expected an incomplete product")
            return
        }
        #expect(partial.nameEn == "Mystery")
        await #expect(throws: ProductLookupError.unavailable) { try await service.lookup("6221000000027") }
        await #expect(throws: ProductLookupError.invalidBarcode) { try await service.lookup("123") }
    }

    @Test func savingTwiceUpdatesOneProduct() throws {
        let (service, context) = try makeService()
        var info = ProductInfo(barcode: "6221000000010", nameAr: "أ", nameEn: "A", per100: Macros(kcal: 100, protein: 1, carbs: 2, fat: 3),
                               source: .label)
        service.save(info, now: Date(timeIntervalSince1970: 0))
        info.nameEn = "B"
        info.source = .manual
        service.save(info, now: Date(timeIntervalSince1970: 100))
        let products = try context.fetch(FetchDescriptor<Product>())
        #expect(products.count == 1)
        #expect(products.first?.nameEn == "B")
        #expect(products.first?.source == .manual)
        #expect(products.first?.lastUsedAt == Date(timeIntervalSince1970: 100))
    }

    @Test func productDraftItemCarriesTheBarcode() {
        let info = ProductInfo(barcode: "6221000000010", nameAr: "", nameEn: "Crackers", servingGrams: 30,
                               per100: Macros(kcal: 480, protein: 9, carbs: 62, fat: 21), source: .openFoodFacts)
        let item = info.draftItem(grams: 30)
        #expect(item.nameAr == "Crackers")
        #expect(abs(item.totals.kcal - 144) < 0.001)
        #expect(item.makeMealItem().barcode == "6221000000010")
        #expect(item.makeMealItem().valueSourceRaw == "product")
    }
}

struct ProductLabelTests {
    private func decode(_ json: String) throws -> ProductLabel {
        try JSONDecoder().decode(ProductLabel.self, from: Data(json.utf8))
    }

    @Test func validLabelBecomesALabelProduct() throws {
        let label = try decode(#"{"nameAr":"بسكويت","nameEn":" Biscuits ","brand":"","servingGrams":25,"per100":{"kcal":400,"protein":10,"carbs":60,"fat":13},"readable":true,"notes":null}"#)
        try label.validate()
        let info = label.info(barcode: "6221000000010")
        #expect(info.nameEn == "Biscuits")
        #expect(info.brand == nil)
        #expect(info.source == .label)
        #expect(info.per100?.kcal == 400)
    }

    @Test func rejectsImplausibleValues() throws {
        let kilojoules = try decode(#"{"nameAr":"x","nameEn":"x","brand":null,"servingGrams":null,"per100":{"kcal":1700,"protein":10,"carbs":60,"fat":13},"readable":true,"notes":null}"#)
        #expect(throws: AIValidationError.self) { try kilojoules.validate() }
        let tooMuch = try decode(#"{"nameAr":"x","nameEn":"x","brand":null,"servingGrams":null,"per100":{"kcal":400,"protein":50,"carbs":60,"fat":13},"readable":true,"notes":null}"#)
        #expect(throws: AIValidationError.self) { try tooMuch.validate() }
    }

    @Test func unreadableLabelSkipsValueChecks() throws {
        let label = try decode(#"{"nameAr":"","nameEn":"","brand":null,"servingGrams":null,"per100":{"kcal":0,"protein":0,"carbs":0,"fat":0},"readable":false,"notes":"blurry"}"#)
        try label.validate()
    }

    @Test func labelPromptLoadsWithoutPlaceholders() {
        let prompt = PromptLibrary.load("label")
        #expect(prompt.contains("per 100 g"))
        #expect(prompt.contains("<user_content>"))
        #expect(prompt.contains("{{LANGUAGE_NAME}}"))   // filled in by readLabel
    }
}
