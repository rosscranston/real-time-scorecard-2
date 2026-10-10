import Foundation
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

@main
struct ScorecardProbe {
    @MainActor static func main() async {
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
            let packURL = root.appendingPathComponent("tests/Fixtures/synthetic-discovery-calls.json")
            let pack = try ScorecardCoding.decoder().decode(SyntheticCallPack.self, from: Data(contentsOf: packURL))
            let id = argument("--call", fallback: "01-owner-story")
            guard let script = pack.calls.first(where: { $0.id == id }) else { throw OpenAIError.invalidResponse }
            guard let key = CredentialStore.developerKey(directory: root) else { throw OpenAIError.missingKey }
            let config = try ScorecardConfiguration.load(Data(contentsOf: root.appendingPathComponent("configurations/company-scorecard.draft.json")))
            let company = CompanyScorecard(name: "Replay: \(script.title)", configuration: config)
            var call = CallRecord(company: company, isReplay: true)
            call.eventName = script.title
            let reportDirectory = root.appendingPathComponent("test-results/\(id)-\(Int(Date().timeIntervalSince1970))")
            try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
            let database = try ScorecardDatabase(url: reportDirectory.appendingPathComponent("replay.sqlite3"))
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
            let sentences = Array(script.sentences(callID: call.id).prefix(max(1, limit)))
            print("Replay \(id): \(sentences.count) sentences, every \(interval)s, real Decisions + Responses.")
            print("Arrival-to-persisted-fact timing; excludes transcription and screen rendering.")
            fflush(stdout)
            let start = ContinuousClock.now
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
            let p95 = times.isEmpty ? 0 : times[min(times.count - 1, Int(ceil(Double(times.count) * 0.95)) - 1)]
            let spend = await client.usage().chargedOrReservedUSD - initialSpend
            let results: [String: Any] = [
                "call": id, "interval_seconds": interval,
                "sentences_sent": session.segments.count, "sentences_processed": times.count,
                "p95_seconds": p95, "within_5_seconds": times.filter { $0 <= 5 }.count,
                "estimated_cost_usd": spend, "pending": session.pendingCount,
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
