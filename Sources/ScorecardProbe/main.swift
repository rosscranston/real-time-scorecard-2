import Foundation
import Darwin
import CryptoKit
import ScorecardCore

// Replay-only diagnostics. Never record request headers, keys, or live customer data.
private struct SyntheticRecordingTransport: HTTPTransport {
    let directory: URL
    let base = URLSessionTransport()
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let result = try await base.send(request)
        let endpoint = request.url?.lastPathComponent ?? "api"
        let file = "\(Int(Date().timeIntervalSince1970 * 1000))-\(endpoint)-\(UUID().uuidString).json"
        try result.0.write(to: directory.appendingPathComponent(file), options: .atomic)
        return result
    }
}
private final class TranscriptCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [AudioTranscriptEvent] = []
    private var errors: [String] = []
    func append(_ event: AudioTranscriptEvent) { lock.withLock { events.append(event) } }
    func fail(_ message: String) { lock.withLock { errors.append(message) } }
    func result() -> ([AudioTranscriptEvent], [String]) { lock.withLock { (events, errors) } }
}

@main
struct ScorecardProbe {
    @MainActor static func main() async {
        if CommandLine.arguments.contains("--audio-smoke") {
            await audioSmoke()
            return
        }
        if CommandLine.arguments.contains("--save-key") {
            do {
                guard let key = CredentialStore.developerKey(directory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) else {
                    throw OpenAIError.missingKey
                }
                try CredentialStore.save(key)
                print("Saved the configured development key to this app's local Keychain entry. No network request sent.")
            } catch {
                print("Could not save the configured key to Keychain."); exit(1)
            }
            return
        }
        if CommandLine.arguments.contains("--replay") {
            await runReplay()
            return
        }
        guard CommandLine.arguments.contains("--live-sample") else {
            print("Use --live-sample to run one bounded synthetic extraction through the real core pipeline.")
            return
        }
        do {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            guard let key = CredentialStore.developerKey(directory: root) else { throw OpenAIError.missingKey }
            let config = try ScorecardConfiguration.load(Data(contentsOf: root.appendingPathComponent("configurations/company-scorecard.draft.json")))
            var company = CompanyScorecard(name: "Synthetic Example Firm", configuration: config)
            let call = CallRecord(company: company, isReplay: true)
            let segment = TranscriptEntry(callID: call.id, sequence: 1, speaker: .customer,
                                          text: "We use Drake Desktop. It runs on a local computer in our office. Our team has 6 people. We prepare 800 returns per year.")
            let job = ExtractionJob(company: company, callID: call.id, configuration: config, segments: [segment])
            let client = try OpenAIClient(key: key, ledgerURL: root.appendingPathComponent("private-data/api-test-usage.json"))
            let result = try await CloudExtractor(client: client).extract(job: job, company: company, configuration: config)
            for candidate in result.candidates {
                _ = FactReducer.apply(candidate, job: job, currentSegments: [segment.id: segment], configuration: config, company: &company)
            }
            let expected: [String: JSONValue] = [
                "tax_software": .string("Drake Desktop"), "hosting_deal": .string("Local computer"),
                "employee_count": .number(6), "number_of_returns": .number(800)
            ]
            var failures = 0
            for key in expected.keys.sorted() {
                let fact = company.facts[key]
                let matched = fact?.value == expected[key]
                if !matched { failures += 1 }
                print("\(matched ? "PASS" : "FAIL") \(key): \(fact?.display ?? "?")")
            }
            print(String(format: "Two-stage concurrent extraction: %.2fs. Transcript-only benchmark.", result.seconds))
            print("Candidates: \(result.candidates.count); validation warnings: \(result.warnings.count)")
            let usage = await client.usage()
            print(String(format: "Ledger estimated/reserved spend: $%.6f", usage.chargedOrReservedUSD))
            exit(failures == 0 ? 0 : 1)
        } catch {
            // Known errors are sanitized; never print arbitrary provider response text.
            if let error = error as? OpenAIError { print(error.localizedDescription) }
            else if let error = error as? ConfigurationError { print(error.localizedDescription) }
            else { print("Probe failed while loading configuration, credentials, or validating the API response.") }
            exit(1)
        }
    }

    @MainActor static func audioSmoke() async {
        do {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            guard let key = CredentialStore.developerKey(directory: root) else { throw OpenAIError.missingKey }
            let pcm = try Data(contentsOf: root.appendingPathComponent("test-results/audio/discovery-smoke.pcm"))
            let duration = Double(pcm.count) / 48000
            guard duration > 1, duration <= 20 else { throw OpenAIError.invalidResponse }
            let client = try OpenAIClient(key: key, ledgerURL: root.appendingPathComponent("private-data/api-test-usage.json"))
            try await client.reserveAudioTest(seconds: duration)
            let collector = TranscriptCollector()
            let transcriber = OpenAITranscriber(key: key, role: .customer, origin: Date(),
                keywords: ["Drake", "Drake Desktop"], onEvent: { collector.append($0) }, onError: { collector.fail($0) })
            try await transcriber.start()
            print("Audio session connected. Sending \(String(format: "%.2f", duration)) seconds of synthetic speech.")
            try await transcriber.submit(AudioTurn(pcm16: pcm, startSeconds: 0, endSeconds: duration))
            await transcriber.finish()
            let (events, errors) = collector.result()
            guard errors.isEmpty, !events.isEmpty else {
                print("No complete transcription. \(errors.first ?? "")"); exit(1)
            }
            let text = events.sorted { $0.startSeconds < $1.startSeconds }.map(\.text).joined(separator: " ")
            try text.write(to: root.appendingPathComponent("test-results/audio/transcribed.txt"), atomically: true, encoding: .utf8)
            print("Synthetic audio transcript: \(text)")
            let config = try ScorecardConfiguration.load(Data(contentsOf: root.appendingPathComponent("configurations/company-scorecard.draft.json")))
            var company = CompanyScorecard(name: "Synthetic audio roundtrip", configuration: config)
            let call = CallRecord(company: company, isReplay: true)
            let segment = TranscriptEntry(callID: call.id, sequence: 1, speaker: .customer, text: text)
            let job = ExtractionJob(company: company, callID: call.id, configuration: config, segments: [segment])
            let result = try await CloudExtractor(client: client).extract(job: job, company: company, configuration: config)
            for candidate in result.candidates {
                _ = FactReducer.apply(candidate, job: job, currentSegments: [segment.id: segment], configuration: config, company: &company)
            }
            let expected: [String: JSONValue] = ["tax_software": .string("Drake Desktop"), "employee_count": .number(6), "number_of_returns": .number(800)]
            let passed = expected.allSatisfy { company.facts[$0.key]?.value == $0.value }
            print("Audio → transcript → scorecard: \(passed ? "PASS" : "FAIL") for software, team size and return count.")
            exit(passed ? 0 : 1)
        } catch {
            print((error as? OpenAIError)?.localizedDescription ?? "Synthetic audio test failed.")
            exit(1)
        }
    }

    @MainActor static func runReplay() async {
        func argument(_ flag: String, fallback: String) -> String {
            guard let index = CommandLine.arguments.firstIndex(of: flag),
                  index + 1 < CommandLine.arguments.count else { return fallback }
            return CommandLine.arguments[index + 1]
        }
        do {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let interval = Double(argument("--interval", fallback: "5")) ?? 5
            guard interval >= 3, interval <= 30 else { throw OpenAIError.invalidResponse }
            let soakMinutes = Int(argument("--soak-minutes", fallback: "0")) ?? 0
            guard [0, 45].contains(soakMinutes) else { throw OpenAIError.invalidResponse }
            let packURL = root.appendingPathComponent(CommandLine.arguments.contains("--short")
                ? "tests/Fixtures/synthetic-short-calls.json" : "tests/Fixtures/synthetic-discovery-calls.json")
            let packData = try Data(contentsOf: packURL)
            let pack = try ScorecardCoding.decoder().decode(SyntheticCallPack.self, from: packData)
            let id = argument("--call", fallback: "01-owner-story")
            guard let script = pack.calls.first(where: { $0.id == id }) else { throw OpenAIError.invalidResponse }
            guard let key = CredentialStore.developerKey(directory: root) else { throw OpenAIError.missingKey }
            let config = try ScorecardConfiguration.load(Data(contentsOf: root.appendingPathComponent("configurations/company-scorecard.draft.json")))
            var company = CompanyScorecard(name: "Replay: \(script.title)", configuration: config)
            var call = CallRecord(company: company, isReplay: true)
            call.eventName = script.title
            let resumePath = argument("--resume", fallback: "")
            guard soakMinutes == 0 || resumePath.isEmpty else { throw OpenAIError.invalidResponse }
            let reportDirectory = resumePath.isEmpty ? root.appendingPathComponent("test-results/\(id)-\(Int(Date().timeIntervalSince1970))") : URL(fileURLWithPath: resumePath)
            try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
            let database = try ScorecardDatabase(url: reportDirectory.appendingPathComponent("replay.sqlite3"))
            if !resumePath.isEmpty {
                guard let previousCall = try database.calls().first, previousCall.eventName == script.title,
                      let previousCompany = try database.company(id: previousCall.companyID, configurationID: config.id),
                      previousCompany.configurationRevision == config.revision else { throw OpenAIError.invalidResponse }
                call = previousCall; call.endedAt = nil; company = previousCompany
                for filename in ["report.json", "measurements.json"] {
                    let url = reportDirectory.appendingPathComponent(filename)
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.copyItem(at: url, to: reportDirectory.appendingPathComponent("before-resume-\(Int(Date().timeIntervalSince1970))-\(filename)"))
                    }
                }
            }
            let wireDirectory = reportDirectory.appendingPathComponent("synthetic-responses")
            try FileManager.default.createDirectory(at: wireDirectory, withIntermediateDirectories: true)
            let client = try OpenAIClient(key: key, transport: SyntheticRecordingTransport(directory: wireDirectory),
                                         ledgerURL: root.appendingPathComponent("private-data/api-test-usage.json"))
            let initialSpend = await client.usage().chargedOrReservedUSD
            let session = try ExtractionSession(company: company, call: call, configuration: config,
                                                database: database, extractor: CloudExtractor(client: client))
            session.onMeasurement = { measurement in
                print(String(format: "DONE sentence %d: %.2fs total, %.2fs queue, %d changes, %d warnings",
                             measurement.sequence, measurement.totalSeconds, measurement.queueSeconds,
                             measurement.updates, measurement.warnings.count))
                fflush(stdout)
            }
            let limit = Int(argument("--limit", fallback: "10000")) ?? 10000
            let lastExistingSequence = session.segments.map(\.sequence).max() ?? 0
            let original = script.sentences(callID: call.id)
            var sentences = Array(original.filter { $0.sequence > lastExistingSequence }.prefix(max(1, limit)))
            if soakMinutes > 0 {
                guard !original.isEmpty else { throw OpenAIError.invalidResponse }
                let count = Int(Double(soakMinutes * 60) / interval) + 1
                sentences = (0..<count).map { index in
                    var segment = original[index % original.count]
                    segment.id = UUID(); segment.sequence = index + 1; segment.seconds = Double(index) * interval
                    return segment
                }
                print("SOAK: repeating synthetic conversation for 45 minutes; final partial-cycle facts are not an accuracy benchmark.")
            }
            print("Replay \(id): \(sentences.count) sentences, every \(interval)s, real Decisions + Responses.")
            print("Arrival-to-persisted-fact timing; excludes transcription and screen rendering.")
            fflush(stdout)
            session.resume()
            let start = ContinuousClock.now
            let wallStart = Date()
            for (index, var sentence) in sentences.enumerated() {
                // Deadline is anchored to the producer, never to API completion.
                try await ContinuousClock().sleep(until: start + .milliseconds(Int64(Double(index) * interval * 1000)))
                sentence.receivedAt = Date(); sentence.sentenceEndedAt = sentence.receivedAt
                try session.ingest(sentence)
                print("ARRIVE \(sentence.sequence) [\(sentence.speaker.rawValue)] pending=\(session.pendingCount)")
                fflush(stdout)
                if session.errorMessage != nil { break }
            }
            await session.waitUntilIdle()
            try session.finish()
            let times = session.measurements.map(\.totalSeconds).sorted()
            let updateTimes = session.measurements.filter { $0.updates > 0 }.map(\.totalSeconds).sorted()
            let p95 = times.isEmpty ? 0 : times[min(times.count - 1, Int(ceil(Double(times.count) * 0.95)) - 1)]
            let spend = await client.usage().chargedOrReservedUSD - initialSpend
            var resources = rusage()
            getrusage(RUSAGE_SELF, &resources)
            let cpuSeconds = Double(resources.ru_utime.tv_sec + resources.ru_stime.tv_sec)
                + Double(resources.ru_utime.tv_usec + resources.ru_stime.tv_usec) / 1_000_000
            let results: [String: Any] = [
                "call": id, "interval_seconds": interval,
                "fixture_sha256": SHA256.hash(data: packData).map { String(format: "%02x", $0) }.joined(),
                "configuration_id": config.id, "configuration_revision": config.revision,
                "configuration_sha256": SHA256.hash(data: try ScorecardCoding.encoder().encode(config)).map { String(format: "%02x", $0) }.joined(),
                "sentences_sent": session.segments.count, "sentences_processed": times.count,
                "p95_seconds": p95, "within_5_seconds": times.filter { $0 <= 5 }.count,
                "updates_measured": updateTimes.count,
                "update_p95_seconds": updateTimes.isEmpty ? 0 : updateTimes[min(updateTimes.count - 1, Int(ceil(Double(updateTimes.count) * 0.95)) - 1)],
                "updates_within_5_seconds": updateTimes.filter { $0 <= 5 }.count,
                "estimated_cost_usd": spend, "pending": session.pendingCount,
                "resumed": !resumePath.isEmpty,
                "soak_minutes_requested": soakMinutes,
                "wall_seconds": Date().timeIntervalSince(wallStart),
                "process_cpu_seconds": cpuSeconds,
                "process_peak_rss_bytes": resources.ru_maxrss,
                "error": session.errorMessage as Any? ?? NSNull(),
                "facts": session.company.facts.mapValues { ["value": $0.display, "confidence": $0.confidence] as [String: Any] },
                "scope": "Synthetic transcript arrival to SQLite commit; not audio-to-screen latency."
            ]
            try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
                .write(to: reportDirectory.appendingPathComponent("report.json"), options: .atomic)
            try JSONEncoder().encode(session.measurements).write(to: reportDirectory.appendingPathComponent("measurements.json"))
            print(String(format: "RESULT processed=%d/%d p95=%.2fs estimated=$%.5f", times.count, session.segments.count, p95, spend))
            print("Report: \(reportDirectory.path)")
            if let error = session.errorMessage { print(error); exit(1) }
        } catch {
            print((error as? OpenAIError)?.localizedDescription ?? "Replay could not run; inspect local fixture/configuration and database access.")
            exit(1)
        }
    }
}
