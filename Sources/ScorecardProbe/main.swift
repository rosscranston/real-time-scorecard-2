import Foundation
import ScorecardCore

@main
struct ScorecardProbe {
    static func main() async {
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
}
