import Foundation

enum AgentSessionCostCalculator {
    private struct Pricing {
        let input: Double
        let output: Double
        let cacheRead: Double
        let cacheWrite: Double
    }

    static func codexCost(from data: Data) -> Double? {
        var model: String?
        var usage: [String: Any]?

        for line in data.split(separator: 0x0A) {
            guard let object = jsonObject(line),
                  let type = object["type"] as? String
            else { continue }
            let payload = object["payload"] as? [String: Any]
            if type == "turn_context", let value = payload?["model"] as? String {
                model = value
            } else if type == "event_msg",
                      payload?["type"] as? String == "token_count",
                      let info = payload?["info"] as? [String: Any],
                      let total = info["total_token_usage"] as? [String: Any] {
                usage = total
            }
        }

        guard let model,
              let pricing = codexPricing(for: model),
              let usage
        else { return nil }
        let input = integer(usage["input_tokens"])
        let cached = min(input, integer(usage["cached_input_tokens"]))
        let output = integer(usage["output_tokens"])
        return cost(
            input: input - cached,
            output: output,
            cacheRead: cached,
            cacheWrite: 0,
            pricing: pricing
        )
    }

    static func claudeCost(from data: Data) -> Double? {
        var messages: [String: (model: String, usage: [String: Any])] = [:]
        var unkeyedIndex = 0

        for line in data.split(separator: 0x0A) {
            guard let object = jsonObject(line),
                  object["type"] as? String == "assistant",
                  let message = object["message"] as? [String: Any],
                  let model = message["model"] as? String,
                  let usage = message["usage"] as? [String: Any]
            else { continue }
            let key = (message["id"] as? String)
                ?? (object["requestId"] as? String)
                ?? "unkeyed-\(unkeyedIndex)"
            unkeyedIndex += 1
            messages[key] = (model, usage)
        }

        var total = 0.0
        var pricedMessageCount = 0
        for message in messages.values {
            guard let pricing = claudePricing(for: message.model) else { continue }
            total += cost(
                input: integer(message.usage["input_tokens"]),
                output: integer(message.usage["output_tokens"]),
                cacheRead: integer(message.usage["cache_read_input_tokens"]),
                cacheWrite: integer(message.usage["cache_creation_input_tokens"]),
                pricing: pricing
            )
            pricedMessageCount += 1
        }
        return pricedMessageCount > 0 ? total : nil
    }

    private static func cost(
        input: Int,
        output: Int,
        cacheRead: Int,
        cacheWrite: Int,
        pricing: Pricing
    ) -> Double {
        (Double(input) * pricing.input
            + Double(output) * pricing.output
            + Double(cacheRead) * pricing.cacheRead
            + Double(cacheWrite) * pricing.cacheWrite) / 1_000_000
    }

    private static func codexPricing(for rawModel: String) -> Pricing? {
        let model = rawModel == "gpt-5.6" ? "gpt-5.6-sol" : rawModel
        let prices: [String: Pricing] = [
            "gpt-5": .init(input: 1.25, output: 10, cacheRead: 0.125, cacheWrite: 1.25),
            "gpt-5-codex": .init(input: 1.25, output: 10, cacheRead: 0.125, cacheWrite: 1.25),
            "gpt-5-mini": .init(input: 0.25, output: 2, cacheRead: 0.025, cacheWrite: 0.25),
            "gpt-5-nano": .init(input: 0.05, output: 0.4, cacheRead: 0.005, cacheWrite: 0.05),
            "gpt-5.1": .init(input: 1.25, output: 10, cacheRead: 0.125, cacheWrite: 1.25),
            "gpt-5.1-codex": .init(input: 1.25, output: 10, cacheRead: 0.125, cacheWrite: 1.25),
            "gpt-5.1-codex-max": .init(input: 1.25, output: 10, cacheRead: 0.125, cacheWrite: 1.25),
            "gpt-5.1-codex-mini": .init(input: 0.25, output: 2, cacheRead: 0.025, cacheWrite: 0.25),
            "gpt-5.2": .init(input: 1.75, output: 14, cacheRead: 0.175, cacheWrite: 1.75),
            "gpt-5.2-codex": .init(input: 1.75, output: 14, cacheRead: 0.175, cacheWrite: 1.75),
            "gpt-5.3-codex": .init(input: 1.75, output: 14, cacheRead: 0.175, cacheWrite: 1.75),
            "gpt-5.3-codex-spark": .init(input: 0, output: 0, cacheRead: 0, cacheWrite: 0),
            "gpt-5.4": .init(input: 2.5, output: 15, cacheRead: 0.25, cacheWrite: 2.5),
            "gpt-5.4-mini": .init(input: 0.75, output: 4.5, cacheRead: 0.075, cacheWrite: 0.75),
            "gpt-5.4-nano": .init(input: 0.2, output: 1.25, cacheRead: 0.02, cacheWrite: 0.2),
            "gpt-5.5": .init(input: 5, output: 30, cacheRead: 0.5, cacheWrite: 5),
            "gpt-5.6-sol": .init(input: 5, output: 30, cacheRead: 0.5, cacheWrite: 6.25),
            "gpt-5.6-terra": .init(input: 2.5, output: 15, cacheRead: 0.25, cacheWrite: 3.125),
            "gpt-5.6-luna": .init(input: 1, output: 6, cacheRead: 0.1, cacheWrite: 1.25),
        ]
        return prices[model]
    }

    private static func claudePricing(for model: String) -> Pricing? {
        if model.contains("haiku-4-5") {
            return .init(input: 1, output: 5, cacheRead: 0.1, cacheWrite: 1.25)
        }
        if model.contains("sonnet-5") || model.contains("sonnet-4") {
            return .init(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75)
        }
        if model.contains("fable-5") {
            return .init(input: 10, output: 50, cacheRead: 1, cacheWrite: 12.5)
        }
        if model.contains("opus-4-5") || model.contains("opus-4-6")
            || model.contains("opus-4-7") || model.contains("opus-4-8") {
            return .init(input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25)
        }
        if model.contains("opus-4") {
            return .init(input: 15, output: 75, cacheRead: 1.5, cacheWrite: 18.75)
        }
        return nil
    }

    private static func jsonObject(_ line: Data.SubSequence) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
    }

    private static func integer(_ value: Any?) -> Int {
        if let value = value as? NSNumber { return max(0, value.intValue) }
        if let value = value as? String, let number = Int(value) {
            return max(0, number)
        }
        return 0
    }
}
