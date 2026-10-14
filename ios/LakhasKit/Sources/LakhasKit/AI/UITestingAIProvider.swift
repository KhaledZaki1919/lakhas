import Foundation

/// Canned answers for UI tests (`-uiTestingStubAI`): no network, no key. Never used otherwise.
public struct UITestingAIProvider: AIProvider {
    public let kind = AIProviderKind.anthropic

    public init() {}

    /// Barcodes for UI tests: the first is on (stubbed) Open Food Facts, the second is unknown.
    public static let knownBarcode = "6221000000010"
    public static let unknownBarcode = "6221000000027"

    /// Stands in for Open Food Facts under `-uiTesting`: 30 g serving × 480 kcal/100 g = 144 kcal.
    public static let products: [String: ProductInfo] = [
        knownBarcode: ProductInfo(barcode: knownBarcode, nameAr: "بسكويت تجريبي", nameEn: "Test Crackers", brand: "Lakhas",
                                  servingGrams: 30, per100: Macros(kcal: 480, protein: 9, carbs: 62, fat: 21),
                                  source: .openFoodFacts),
    ]

    public func complete(_ request: AIRequest, model: String, structured: Bool) async throws -> AIResponse {
        if request.schemaName == "product_label" {
            // 25 g serving × 400 kcal/100 g = 100 kcal
            let text = """
            {"nameAr":"بسكويت الملصق","nameEn":"Label Biscuits","brand":"Lakhas","servingGrams":25,\
            "per100":{"kcal":400,"protein":10,"carbs":60,"fat":13},"readable":true,"notes":null}
            """
            return AIResponse(text: text, usage: AIUsage(inputTokens: 1500, outputTokens: 60), model: "claude-haiku-5-5")
        }
        let isCorrection = request.userText.contains("<current_items>")
        let grams = isCorrection ? 300 : 450
        let text = """
        {"items":[{"nameAr":"كشري","nameEn":"Koshary","grams":\(grams),"confidence":0.9,\
        "per100":{"kcal":156,"protein":4.9,"carbs":25,"fat":4},"foodDbId":"eg-koshary","leftoverGrams":null}],"notes":null}
        """
        return AIResponse(text: text, usage: AIUsage(inputTokens: 1200, outputTokens: 80), model: "claude-haiku-5-5")
    }

    public func listModels() async throws -> [String] { ["claude-haiku-5-5"] }
}
