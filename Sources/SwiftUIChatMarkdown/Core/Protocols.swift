import Foundation

/// Protocol defining remote data operations for chat session synchronization.
/// Conformers must be thread-safe (`Sendable`) as they execute across background actors.
public protocol ChatSessionDataSource: AnyObject, Sendable {
    /// Fetches chat message transcript history from a remote API for a given session.
    /// - Parameter sessionKey: The unique identifier key of the chat session.
    /// - Returns: An array of messages from the server.
    func fetchRemoteHistory(sessionKey: String) async throws -> [SDKChatMessage]
}

/// Protocol defining local storage and cache capabilities for persistence.
/// Conformers are required to be thread-safe (`Sendable`).
public protocol ChatMessageCache: AnyObject, Sendable {
    /// Loads a list of cached chat session summaries, sorted by last updated timestamp.
    /// - Returns: An array of session summaries.
    func loadSessions() async -> [SDKChatSessionEntry]
    
    /// Loads the message history transcript cached under a specific session key.
    /// - Parameter sessionKey: The unique identifier key of the session.
    /// - Returns: The cached message array, or empty if not present.
    func loadTranscript(sessionKey: String) async -> [SDKChatMessage]
    
    /// Caches the given message transcript for a session.
    /// - Parameters:
    ///   - sessionKey: The unique identifier key of the session.
    ///   - messages: The array of messages to store (normally trimmed to avoid heavy payloads).
    func storeTranscript(sessionKey: String, messages: [SDKChatMessage]) async
    
    /// Stores the list of session summaries back to cache.
    /// - Parameter sessions: The list of session entries to persist.
    func storeSessions(_ sessions: [SDKChatSessionEntry]) async
}

/// A session entry summary representation of a chat history channel.
public struct SDKChatSessionEntry: Codable, Equatable, Sendable {
    /// The unique key identifying this chat thread.
    public let sessionKey: String
    /// The user-visible title or description of this chat session.
    public let title: String
    /// The last update timestamp for ordering in lists.
    public let updatedAt: Date

    public init(sessionKey: String, title: String, updatedAt: Date) {
        self.sessionKey = sessionKey
        self.title = title
        self.updatedAt = updatedAt
    }
}
