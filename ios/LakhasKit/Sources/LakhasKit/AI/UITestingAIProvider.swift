import Foundation

/// Canned answers for UI tests (`-uiTestingStubAI`): no network, no key. Never used otherwise.
public struct UITestingAIProvider: AIProvider {
    public let kind = AIProviderKind.anthropic

    public init() {}

    public func complete(_ request: AIRequest, model: String, structured: Bool) async throws -> AIResponse {
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
