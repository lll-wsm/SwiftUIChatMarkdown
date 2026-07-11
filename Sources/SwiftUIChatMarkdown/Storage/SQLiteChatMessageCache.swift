import Foundation
import SQLite3

/// Actor-isolated local storage database utilizing the C SQLite3 API.
/// Performs transaction-backed thread-safe operations in a background context, ensuring the main UI thread never blocks.
public actor SQLiteChatMessageCache: ChatMessageCache {
    /// Helper connection wrapper executing `sqlite3_close_v2` on deinitialization.
    private final class Connection: @unchecked Sendable {
        let raw: OpaquePointer

        init(raw: OpaquePointer) {
            self.raw = raw
        }

        deinit {
            sqlite3_close_v2(self.raw)
        }
    }

    private let databaseURL: URL
    private var db: Connection?

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    private func getDatabase() -> OpaquePointer? {
        if let db = db {
            return db.raw
        }

        let fileManager = FileManager.default
        let directoryURL = databaseURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX

        guard sqlite3_open_v2(databaseURL.path, &opened, flags, nil) == SQLITE_OK, let dbPointer = opened else {
            if let opened = opened {
                sqlite3_close_v2(opened)
            }
            return nil
        }

        sqlite3_exec(dbPointer, "PRAGMA journal_mode=WAL;", nil, nil, nil)

        guard createSchema(dbPointer) else {
            sqlite3_close_v2(dbPointer)
            return nil
        }

        self.db = Connection(raw: dbPointer)
        return dbPointer
    }

    private func createSchema(_ db: OpaquePointer) -> Bool {
        let sqlSessions = """
        CREATE TABLE IF NOT EXISTS cached_sessions(
            session_key TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        """

        let sqlTranscripts = """
        CREATE TABLE IF NOT EXISTS cached_transcripts(
            session_key TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        """

        guard sqlite3_exec(db, sqlSessions, nil, nil, nil) == SQLITE_OK else { return false }
        guard sqlite3_exec(db, sqlTranscripts, nil, nil, nil) == SQLITE_OK else { return false }
        return true
    }

    public func loadSessions() async -> [SDKChatSessionEntry] {
        guard let db = getDatabase() else { return [] }

        var stmt: OpaquePointer?
        let sql = "SELECT session_key, title, updated_at FROM cached_sessions ORDER BY updated_at DESC;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var sessions: [SDKChatSessionEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let sessionKey = sqlite3_column_text(stmt, 0),
                  let title = sqlite3_column_text(stmt, 1)
            else {
                continue
            }

            let updatedAtDouble = sqlite3_column_double(stmt, 2)
            let updatedAt = Date(timeIntervalSince1970: updatedAtDouble)

            sessions.append(SDKChatSessionEntry(
                sessionKey: String(cString: sessionKey),
                title: String(cString: title),
                updatedAt: updatedAt
            ))
        }

        return sessions
    }

    public func storeSessions(_ sessions: [SDKChatSessionEntry]) async {
        guard let db = getDatabase() else { return }

        sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil)
        var committed = false
        defer {
            if !committed {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            }
        }

        guard sqlite3_exec(db, "DELETE FROM cached_sessions;", nil, nil, nil) == SQLITE_OK else {
            return
        }

        var stmt: OpaquePointer?
        let sql = "INSERT INTO cached_sessions (session_key, title, updated_at) VALUES (?, ?, ?);"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        for session in sessions {
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, strdup(session.sessionKey), -1, free)
            sqlite3_bind_text(stmt, 2, strdup(session.title), -1, free)
            sqlite3_bind_double(stmt, 3, session.updatedAt.timeIntervalSince1970)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                return
            }
        }

        if sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK {
            committed = true
        }
    }

    public func loadTranscript(sessionKey: String) async -> [SDKChatMessage] {
        guard let db = getDatabase() else { return [] }

        var stmt: OpaquePointer?
        let sql = "SELECT payload FROM cached_transcripts WHERE session_key = ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, strdup(sessionKey), -1, free)

        guard sqlite3_step(stmt) == SQLITE_ROW,
              let payloadText = sqlite3_column_text(stmt, 0)
        else {
            return []
        }

        let jsonString = String(cString: payloadText)
        guard let data = jsonString.data(using: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SDKChatMessage].self, from: data)) ?? []
    }

    public func storeTranscript(sessionKey: String, messages: [SDKChatMessage]) async {
        guard let db = getDatabase() else { return }

        // Suffix to max 200 messages
        let limitedMessages = messages.suffix(200)

        // Strip binary data to keep SQLite payload light
        let strippedMessages = limitedMessages.map { msg in
            let strippedContent = msg.content.map { content in
                SDKChatMessageContent(
                    type: content.type,
                    text: content.text,
                    mimeType: content.mimeType,
                    fileName: content.fileName,
                    data: nil // Strip binary data!
                )
            }
            return SDKChatMessage(
                id: msg.id,
                role: msg.role,
                content: strippedContent,
                timestamp: msg.timestamp,
                isComplete: msg.isComplete
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(strippedMessages),
              let jsonString = String(data: data, encoding: .utf8)
        else {
            return
        }

        var stmt: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO cached_transcripts (session_key, payload, updated_at) VALUES (?, ?, ?);"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, strdup(sessionKey), -1, free)
        sqlite3_bind_text(stmt, 2, strdup(jsonString), -1, free)
        sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)

        sqlite3_step(stmt)
    }
}
