import Foundation

/// Small transport seam for testing disconnects without recording private audio.
public protocol TranscriptionConnection: Sendable {
    func start() async
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close() async
}

private final class AudioNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public final class OpenAIAudioConnection: TranscriptionConnection, @unchecked Sendable {
    private let session: URLSession
    private let socket: URLSessionWebSocketTask
    public init(key: String) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 3600
        session = URLSession(configuration: config, delegate: AudioNoRedirect(), delegateQueue: nil)
        var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        socket = session.webSocketTask(with: request)
    }
    public func start() async { socket.resume() }
    public func send(_ data: Data) async throws { try await socket.send(.string(String(decoding: data, as: UTF8.self))) }
    public func receive() async throws -> Data {
        switch try await socket.receive() {
        case .data(let data): return data
        case .string(let text): return Data(text.utf8)
        @unknown default: throw OpenAIError.invalidResponse
        }
    }
    public func close() async {
        socket.cancel(with: .normalClosure, reason: nil); session.invalidateAndCancel()
    }
}
