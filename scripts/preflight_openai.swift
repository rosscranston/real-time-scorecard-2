import Foundation

// Synthetic preflight only. No microphone, customer audio, or credential output.
enum ProbeError: Error { case invalidResponse, failed }
func dictionary(_ data: Data) throws -> [String: Any] {
    guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProbeError.invalidResponse }
    return value
}
func receive(_ socket: URLSessionWebSocketTask) async throws -> [String: Any] {
    switch try await socket.receive() {
    case .data(let data): return try dictionary(data)
    case .string(let text): return try dictionary(Data(text.utf8))
    @unknown default: throw ProbeError.invalidResponse
    }
}
func send(_ socket: URLSessionWebSocketTask, _ payload: [String: Any]) async throws {
    let data = try JSONSerialization.data(withJSONObject: payload)
    try await socket.send(.string(String(decoding: data, as: UTF8.self)))
}
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
var key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
if key.isEmpty, let text = try? String(contentsOf: root.appendingPathComponent(".env"), encoding: .utf8) {
    for line in text.components(separatedBy: .newlines) {
        let pair = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        if pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces) == "OPENAI_API_KEY" {
            key = pair[1].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
    }
}
guard !key.isEmpty else { print("FAIL: no key configured."); exit(2) }
let config = URLSessionConfiguration.ephemeral
config.timeoutIntervalForRequest = 20
config.timeoutIntervalForResource = 30
let session = URLSession(configuration: config)
var failed = false
if !CommandLine.arguments.contains("--realtime-only") {
    do {
        let schema: [String: Any] = ["type": "object", "properties": ["returns": ["type": "integer"], "quote": ["type": "string"]], "required": ["returns", "quote"], "additionalProperties": false]
        let effort = CommandLine.arguments.contains("--no-reasoning") ? "none" : "low"
        let payload: [String: Any] = ["model": "gpt-6-luna", "store": false, "reasoning": ["effort": effort], "max_output_tokens": 512, "input": "Extract the number of returns and exact evidence quote from: Customer: We prepare 800 returns per year.", "text": ["format": ["type": "json_schema", "name": "scorecard_probe", "strict": true, "schema": schema]]]
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let started = Date()
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { print("Responses HTTP \(status)"); throw ProbeError.failed }
        let result = try dictionary(data)
        let output = result["output"] as? [[String: Any]] ?? []
        let texts = output.flatMap { $0["content"] as? [[String: Any]] ?? [] }.compactMap { $0["text"] as? String }
        guard let text = texts.first, let parsed = try? dictionary(Data(text.utf8)), parsed["returns"] as? Int == 800,
              let quote = parsed["quote"] as? String, !quote.isEmpty, "Customer: We prepare 800 returns per year.".contains(quote) else { throw ProbeError.invalidResponse }
        print(String(format: "PASS: Responses structured number + exact evidence in %.2fs", Date().timeIntervalSince(started)))
    } catch { failed = true; print("FAIL: Responses preflight (credential and response bodies omitted).") }
}
if !CommandLine.arguments.contains("--responses-only") { do {
    var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!)
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    let socket = session.webSocketTask(with: request)
    socket.resume()
    defer { socket.cancel(with: .normalClosure, reason: nil) }
    let timeout = Task { try? await Task.sleep(nanoseconds: 25_000_000_000); socket.cancel(with: .goingAway, reason: nil) }
    defer { timeout.cancel() }
    let created = try await receive(socket)
    guard let type = created["type"] as? String, type.contains("created") else { throw ProbeError.invalidResponse }
    try await send(socket, ["type": "session.update", "session": ["type": "transcription", "audio": ["input": ["format": ["type": "audio/pcm", "rate": 24000], "transcription": ["model": "gpt-live-transcribe", "languages": ["en"], "delay": "low"], "turn_detection": NSNull()]]]])
    var accepted = false
    for _ in 0..<5 {
        let result = try await receive(socket)
        if (result["type"] as? String)?.contains("updated") == true { accepted = true; break }
        if result["type"] as? String == "error" {
            let error = result["error"] as? [String: Any]
            let code = error?["code"] as? String ?? "unspecified"
            print("Realtime rejected configuration; code: \(code.prefix(80))")
            break
        }
    }
    guard accepted else { throw ProbeError.failed }
    print("PASS: Realtime transcription session accepted gpt-live-transcribe. Audio transcription not tested by this probe.")
} catch { failed = true; print("FAIL: Realtime transcription preflight (credential and response bodies omitted).") } }
session.invalidateAndCancel()
exit(failed ? 1 : 0)
