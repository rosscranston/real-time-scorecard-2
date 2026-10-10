import Foundation

public enum OpenAIError: Error, LocalizedError, Equatable {
    case missingKey, authentication, quota, rateLimited, budget, invalidResponse, server(Int), network
    public var errorDescription: String? {
        switch self {
        case .missingKey: return "Add your OpenAI API key in Settings → Connections."
        case .authentication: return "OpenAI rejected this key or this project's permissions."
        case .quota: return "OpenAI reports exhausted credits/quota. Check API billing, then retry explicitly."
        case .rateLimited: return "OpenAI is rate-limiting requests. Pending transcript work is retained."
        case .budget: return "The configured local API allowance has been reached."
        case .invalidResponse: return "The model response failed validation. Existing answers were preserved."
        case .server(let status): return "OpenAI request failed (HTTP \(status))."
        case .network: return "OpenAI could not be reached. Pending transcript work is retained."
        }
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw OpenAIError.invalidResponse }
        return (data, response)
    }
}

public struct APIUsage: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var endpoint: String
    public var model: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var seconds: Double
    public var estimatedUSD: Double
    public var date: Date = Date()
}
public struct UsageLedger: Codable, Sendable {
    public var chargedOrReservedUSD: Double = 0
    public var requests: [APIUsage] = []
    public init() {}
}

public actor OpenAIClient {
    private let key: String
    private let transport: any HTTPTransport
    private let ledgerURL: URL?
    private var ledger: UsageLedger
    private let budgetUSD: Double
    private var quotaBlockedEndpoints: Set<String> = []
    public init(key: String, transport: any HTTPTransport = URLSessionTransport(),
                ledgerURL: URL? = nil, budgetUSD: Double = 5) throws {
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = transport; self.ledgerURL = ledgerURL; self.budgetUSD = budgetUSD
        if let ledgerURL, FileManager.default.fileExists(atPath: ledgerURL.path) {
            // A corrupt ledger is a visible failure, never an excuse to reset spending.
            ledger = try JSONDecoder().decode(UsageLedger.self, from: Data(contentsOf: ledgerURL))
        } else { ledger = UsageLedger() }
    }
    public func usage() -> UsageLedger { ledger }
    public func recordAudioUpload(seconds: Double) throws {
        guard seconds.isFinite, seconds > 0 else { throw OpenAIError.invalidResponse }
        // Reserve one extra second per turn, and retain reservations if transport
        // success is uncertain. Replayed audio is reserved again.
        let estimate = (seconds + 1) / 60 * 0.017
        guard ledger.chargedOrReservedUSD + estimate <= budgetUSD else { throw OpenAIError.budget }
        ledger.chargedOrReservedUSD += estimate
        ledger.requests.append(APIUsage(endpoint: "realtime_audio_estimate", model: "gpt-live-transcribe",
            inputTokens: 0, outputTokens: 0, seconds: seconds, estimatedUSD: estimate))
        try saveLedger()
    }
    public func reserveAudioTest(seconds: Double) throws {
        guard seconds.isFinite, seconds > 0, seconds <= 20 else { throw OpenAIError.budget }
        // Published gpt-live-transcribe rate: $0.017/minute. Reserve two minutes
        // for one bounded <=20-second test, including connection/drain overhead.
        let reservation = 0.034
        guard ledger.chargedOrReservedUSD + reservation <= budgetUSD else { throw OpenAIError.budget }
        ledger.chargedOrReservedUSD += reservation
        ledger.requests.append(APIUsage(endpoint: "realtime_audio_test_reservation", model: "gpt-live-transcribe",
            inputTokens: 0, outputTokens: 0, seconds: seconds, estimatedUSD: reservation))
        try saveLedger()
    }
    public func retryQuotaBlockedEndpoints() { quotaBlockedEndpoints.removeAll() }
    private func saveLedger() throws {
        if let ledgerURL {
            try FileManager.default.createDirectory(at: ledgerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(ledger).write(to: ledgerURL, options: .atomic)
        }
    }
    public func post(endpoint: String, body: Data, maxOutputTokens: Int = 4096) async throws -> Data {
        guard ["decisions", "responses"].contains(endpoint) else { throw OpenAIError.invalidResponse }
        guard !key.isEmpty, !key.contains(where: \.isWhitespace) else { throw OpenAIError.missingKey }
        guard !quotaBlockedEndpoints.contains(endpoint) else { throw OpenAIError.quota }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/\(endpoint)")!)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Conservative upper estimate using UTF-8 bytes as tokens, cache-write rate,
        // output limit, and 2x headroom. Actual standard pricing verified Oct 9 2026.
        let reservation = (Double(body.count + 512) * 0.125 + Double(endpoint == "decisions" ? 0 : maxOutputTokens) * 0.50) / 1_000_000 * 2
        guard reservation.isFinite, budgetUSD.isFinite, budgetUSD > 0,
              ledger.chargedOrReservedUSD + reservation <= budgetUSD else { throw OpenAIError.budget }
        ledger.chargedOrReservedUSD += reservation
        try saveLedger()
        let start = Date()
        let data: Data
        let response: HTTPURLResponse
        do { (data, response) = try await transport.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw OpenAIError.network } // Reservation remains for uncertain billing.
        guard response.statusCode == 200 else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = json?["error"] as? [String: Any]
            let code = error?["code"] as? String ?? ""
            if ["insufficient_quota", "credit_balance_exhausted", "billing_hard_limit_reached"].contains(code) {
                quotaBlockedEndpoints.insert(endpoint); throw OpenAIError.quota
            }
            if [401, 403].contains(response.statusCode) { throw OpenAIError.authentication }
            if response.statusCode == 429 { throw OpenAIError.rateLimited }
            throw OpenAIError.server(response.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw OpenAIError.invalidResponse }
        let usage = json["usage"] as? [String: Any] ?? [:]
        let input = max(0, usage["input_tokens"] as? Int ?? usage["prompt_tokens"] as? Int ?? 0)
        let output = max(0, usage["output_tokens"] as? Int ?? 0)
        let hasUsage = usage["input_tokens"] != nil || usage["prompt_tokens"] != nil
        // Cache writes may cost more than uncached input; use that upper rate for
        // Responses rather than undercounting unrecognized cache usage details.
        let estimated = hasUsage ? (Double(input) * (endpoint == "decisions" ? 0.10 : 0.125) + Double(output) * (endpoint == "decisions" ? 0 : 0.50)) / 1_000_000 : reservation
        ledger.chargedOrReservedUSD = max(0, ledger.chargedOrReservedUSD - reservation + estimated)
        ledger.requests.append(APIUsage(endpoint: endpoint, model: "gpt-6-luna", inputTokens: input,
                                       outputTokens: output, seconds: Date().timeIntervalSince(start), estimatedUSD: estimated))
        try saveLedger()
        return data
    }
}
