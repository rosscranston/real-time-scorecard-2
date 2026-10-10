import Foundation
import CSQLite

public struct DatabaseError: Error, LocalizedError {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

// All entry points serialize through one lock. The UI commits a copied state only after
// saveCompany succeeds, so a disk failure never silently claims that an edit was saved.
public final class ScorecardDatabase: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public static func defaultURL() throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true).appendingPathComponent("LiveScorecard2", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("scorecard.sqlite3")
    }
    public init(url: URL? = nil, inMemory: Bool = false) throws {
        let path = inMemory ? ":memory:" : try (url ?? Self.defaultURL()).path
        if !inMemory {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open database."
            sqlite3_close(db); db = nil; throw DatabaseError(message: message)
        }
        sqlite3_busy_timeout(db, 5000)
        do {
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
            try execute("CREATE TABLE IF NOT EXISTS entities(kind TEXT NOT NULL, id TEXT NOT NULL, company_id TEXT, payload BLOB NOT NULL, updated REAL NOT NULL, PRIMARY KEY(kind,id))")
            try execute("CREATE INDEX IF NOT EXISTS entities_company ON entities(company_id)")
            try execute("CREATE TABLE IF NOT EXISTS changes(id TEXT PRIMARY KEY, company_id TEXT NOT NULL, payload BLOB NOT NULL, created REAL NOT NULL)")
            try execute("PRAGMA user_version=1")
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }

    private func synchronized<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }; return try body()
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func failure() -> DatabaseError { DatabaseError(message: String(cString: sqlite3_errmsg(db))) }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        return statement
    }
    private func bind(_ value: String, _ index: Int32, _ statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, transient)
    }
    private func bind(_ data: Data, _ index: Int32, _ statement: OpaquePointer) {
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), transient) }
    }
    private func write<T: Encodable>(_ value: T, kind: String, id: String, companyID: UUID? = nil) throws {
        let data = try encoder.encode(value)
        let s = try statement("INSERT INTO entities(kind,id,company_id,payload,updated) VALUES(?,?,?,?,?) ON CONFLICT(kind,id) DO UPDATE SET company_id=excluded.company_id,payload=excluded.payload,updated=excluded.updated")
        defer { sqlite3_finalize(s) }
        bind(kind, 1, s); bind(id, 2, s)
        if let companyID { bind(companyID.uuidString, 3, s) } else { sqlite3_bind_null(s, 3) }
        bind(data, 4, s); sqlite3_bind_double(s, 5, Date().timeIntervalSince1970)
        guard sqlite3_step(s) == SQLITE_DONE else { throw failure() }
    }
    private func read<T: Decodable>(_ type: T.Type, kind: String, id: String? = nil, companyID: UUID? = nil) throws -> [T] {
        var sql = "SELECT payload FROM entities WHERE kind=?"
        if id != nil { sql += " AND id=?" }
        if companyID != nil { sql += " AND company_id=?" }
        sql += " ORDER BY updated DESC"
        let s = try statement(sql); defer { sqlite3_finalize(s) }
        bind(kind, 1, s)
        var index: Int32 = 2
        if let id { bind(id, index, s); index += 1 }
        if let companyID { bind(companyID.uuidString, index, s) }
        var result: [T] = []
        while true {
            let code = sqlite3_step(s)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW, let bytes = sqlite3_column_blob(s, 0) else { throw failure() }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(s, 0)))
            result.append(try decoder.decode(type, from: data))
        }
        return result
    }
    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try body(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }
    public func saveCompany(_ company: CompanyScorecard, events: [ChangeEvent] = []) throws {
        try synchronized {
            try transaction {
                try write(company, kind: "company", id: company.storageID, companyID: company.id)
                for event in events {
                    guard event.companyID == company.id, event.configurationID == company.configurationID else {
                        throw DatabaseError(message: "Change event belongs to another company/configuration.")
                    }
                    let s = try statement("INSERT INTO changes(id,company_id,payload,created) VALUES(?,?,?,?)")
                    defer { sqlite3_finalize(s) }
                    bind(event.id.uuidString, 1, s); bind(company.id.uuidString, 2, s)
                    bind(try encoder.encode(event), 3, s); sqlite3_bind_double(s, 4, event.date.timeIntervalSince1970)
                    guard sqlite3_step(s) == SQLITE_DONE else { throw failure() }
                }
            }
        }
    }
    public func companies() throws -> [CompanyScorecard] { try synchronized { try read(CompanyScorecard.self, kind: "company") } }
    public func company(id: UUID, configurationID: String) throws -> CompanyScorecard? {
        try synchronized { try read(CompanyScorecard.self, kind: "company", id: "\(id.uuidString):\(configurationID)").first }
    }
    public func saveConfiguration(_ configuration: ScorecardConfiguration) throws {
        try configuration.validate()
        try synchronized {
            let key = "\(configuration.id):\(configuration.revision)"
            if let existing = try read(ScorecardConfiguration.self, kind: "configuration", id: key).first, existing != configuration {
                throw ConfigurationError.invalid("This configuration revision already exists. Increment revision to save changes.")
            }
            try write(configuration, kind: "configuration", id: key)
        }
    }
    public func configurations() throws -> [ScorecardConfiguration] {
        try synchronized { try read(ScorecardConfiguration.self, kind: "configuration") }
    }
    public func saveCall(_ call: CallRecord) throws {
        try synchronized { try write(call, kind: "call", id: call.id.uuidString, companyID: call.companyID) }
    }
    public func calls(companyID: UUID? = nil) throws -> [CallRecord] {
        try synchronized { try read(CallRecord.self, kind: "call", companyID: companyID).sorted { $0.startedAt > $1.startedAt } }
    }
    @discardableResult
    public func saveSegment(_ segment: TranscriptEntry, companyID: UUID) throws -> Bool {
        try synchronized {
            if let existing = try read(TranscriptEntry.self, kind: "segment", id: segment.id.uuidString).first {
                guard existing.callID == segment.callID else { throw DatabaseError(message: "Segment belongs to another call.") }
                guard segment.revision > existing.revision else { return false }
            }
            guard let call = try read(CallRecord.self, kind: "call", id: segment.callID.uuidString).first,
                  call.companyID == companyID else { throw DatabaseError(message: "Segment has no matching company/call.") }
            try write(segment, kind: "segment", id: segment.id.uuidString, companyID: companyID)
            return true
        }
    }
    public func segments(callID: UUID, companyID: UUID) throws -> [TranscriptEntry] {
        try synchronized {
            try read(TranscriptEntry.self, kind: "segment", companyID: companyID)
                .filter { $0.callID == callID }.sorted { $0.sequence < $1.sequence }
        }
    }
    public func saveIncoming(_ segment: TranscriptEntry, company: CompanyScorecard, job: ExtractionJob?) throws -> Bool {
        try synchronized {
            var inserted = false
            try transaction {
                inserted = try saveSegment(segment, companyID: company.id)
                guard inserted else { return }
                try write(company, kind: "company", id: company.storageID, companyID: company.id)
                if let job {
                    guard job.callID == segment.callID, job.companyID == company.id,
                          job.configurationID == company.configurationID else {
                        throw DatabaseError(message: "Transcript queue identity does not match.")
                    }
                    try write(job, kind: "job", id: job.id.uuidString, companyID: company.id)
                }
            }
            return inserted
        }
    }
    public func saveJob(_ job: ExtractionJob) throws {
        try synchronized { try write(job, kind: "job", id: job.id.uuidString, companyID: job.companyID) }
    }
    public func pendingJobs() throws -> [ExtractionJob] {
        try synchronized {
            try read(ExtractionJob.self, kind: "job").filter { [.pending, .running, .failed].contains($0.status) }.sorted { $0.createdAt < $1.createdAt }
        }
    }
    public func savePreference<T: Encodable>(_ value: T, key: String) throws {
        try synchronized { try write(value, kind: "preference", id: key) }
    }
    public func preference<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
        try synchronized { try read(type, kind: "preference", id: key).first }
    }
    public func changes(companyID: UUID) throws -> [ChangeEvent] {
        try synchronized {
            let s = try statement("SELECT payload FROM changes WHERE company_id=? ORDER BY created")
            defer { sqlite3_finalize(s) }; bind(companyID.uuidString, 1, s)
            var result: [ChangeEvent] = []
            while true {
                let code = sqlite3_step(s)
                if code == SQLITE_DONE { return result }
                guard code == SQLITE_ROW, let bytes = sqlite3_column_blob(s, 0) else { throw failure() }
                result.append(try decoder.decode(ChangeEvent.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(s, 0)))))
            }
        }
    }
    public func deleteCompany(_ id: UUID) throws {
        try synchronized {
            try transaction {
                for table in ["entities", "changes"] {
                    let s = try statement("DELETE FROM \(table) WHERE company_id=?")
                    defer { sqlite3_finalize(s) }; bind(id.uuidString, 1, s)
                    guard sqlite3_step(s) == SQLITE_DONE else { throw failure() }
                }
            }
        }
    }
}
