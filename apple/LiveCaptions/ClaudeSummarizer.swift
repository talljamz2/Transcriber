import Foundation
import Security

/// Summaries, actions and daily recaps written by Claude through the Anthropic API, using the
/// user's own API key. Apple Intelligence still does titles and categories on the device.
enum ClaudeSummarizer {
    enum Model: String, CaseIterable, Identifiable {
        case haiku = "claude-haiku-5-5"
        case sonnet = "claude-sonnet-5-5"
        case opus = "claude-opus-5-5"

        var id: String { rawValue }

        var name: String {
            switch self {
            case .haiku: "Claude Haiku 5.5"
            case .sonnet: "Claude Sonnet 5.5"
            case .opus: "Claude Opus 5.5"
            }
        }

        /// Rough cost for an hour of conversation.
        var costHint: String {
            switch self {
            case .haiku: "under 1¢ per hour of conversation"
            case .sonnet: "about 5¢ per hour of conversation"
            case .opus: "about 10¢ per hour of conversation"
            }
        }
    }

    enum Failure: LocalizedError {
        case badKey, rateLimited, refused, empty, server(String)

        var errorDescription: String? {
            switch self {
            case .badKey: "The Anthropic API key was rejected. Check it in Settings."
            case .rateLimited: "Claude is busy or your usage limit was reached. Try again in a minute."
            case .refused: "Claude declined to summarize this transcript."
            case .empty: "Claude returned an empty summary."
            case .server(let message): message
            }
        }
    }

    static var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: SettingsKey.useClaude) as? Bool ?? true) && APIKeyStore.key != nil
    }

    static var model: Model {
        Model(rawValue: UserDefaults.standard.string(forKey: SettingsKey.claudeModel) ?? "") ?? .haiku
    }

    // MARK: - Session summaries

    struct Digest: Decodable {
        struct Action: Decodable {
            var task: String
            var owner: String   // "speaker_self", "named_person" or "unspecified"
            var person: String
            var due: String
            var dueDate: String
            var quote: String
        }

        var title: String
        var category: String
        var label: String
        var overview: String
        var keyPoints: [String]
        var decisions: [String]
        var actions: [Action]
        var topics: [String]
        var possiblyMisheard: [String]
    }

    private static let digestInstructions = """
    You summarize transcripts for a person with hearing loss who uses live captions to follow and remember \
    conversations, meetings, lectures, phone calls, TV and their own voice notes.

    The transcript comes from automatic speech recognition. It has no speaker labels, it merges voices, and \
    it contains recognition errors. Work out the intended words from context where you can, keep names, \
    numbers, dates and places exactly as said, and never invent anything that isn't supported by the transcript.

    Fill in every field:
    - title: 2 to 6 words naming the subject, like a calendar entry ("Q3 budget review", "Doctor's appointment").
    - category: conversation (informal, in person), meeting (organized discussion of work, plans or decisions), \
    voiceNote (one person talking to themselves: notes, reminders, ideas), phoneCall, lecture (one main speaker \
    presenting: class, talk, sermon, tour), or media (TV, film, sports commentary, news, podcasts, radio, videos).
    - label: under 12 words on what the recording is.
    - overview: 2 to 4 plain sentences on what happened and why it matters to the listener. Be specific; avoid \
    filler like "the speakers discussed various topics".
    - keyPoints: the important things said or learned, each a short, specific sentence.
    - decisions: what was agreed or decided. Empty if nothing was.
    - actions: every task, promise, request, reminder or next step, each starting with a verb. owner is \
    speaker_self when the speaker commits to doing it ("I'll send it", "I need to", "let me"), named_person when \
    a specific person is named as responsible (put the name in person), otherwise unspecified. due is the \
    deadline as said; dueDate is that deadline as YYYY-MM-DD worked out from the recording date, or empty. \
    quote is the short phrase from the transcript the action comes from.
    - topics: 1 to 5 short keywords.
    - possiblyMisheard: garbled passages where the meaning is uncertain, each with your best guess. Empty if none.

    Write in the language of the transcript.
    """

    private static let digestSchema: [String: Any] = {
        let string: [String: Any] = ["type": "string"]
        let strings: [String: Any] = ["type": "array", "items": string]
        let action: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["task", "owner", "person", "due", "dueDate", "quote"],
            "properties": [
                "task": string,
                "owner": ["type": "string", "enum": ["speaker_self", "named_person", "unspecified"]],
                "person": string,
                "due": string,
                "dueDate": string,
                "quote": string,
            ],
        ]
        return [
            "type": "object",
            "additionalProperties": false,
            "required": ["title", "category", "label", "overview", "keyPoints", "decisions", "actions", "topics", "possiblyMisheard"],
            "properties": [
                "title": string,
                "category": ["type": "string", "enum": ["conversation", "meeting", "voiceNote", "phoneCall", "lecture", "media"]],
                "label": string,
                "overview": string,
                "keyPoints": strings,
                "decisions": strings,
                "actions": ["type": "array", "items": action],
                "topics": strings,
                "possiblyMisheard": strings,
            ],
        ]
    }()

    static func digest(transcript: String, header: String) async throws -> Digest {
        let text = try await request(
            system: digestInstructions,
            prompt: "\(header)\n\n<transcript>\n\(transcript)\n</transcript>",
            schema: digestSchema
        )
        return try JSONDecoder().decode(Digest.self, from: Data(text.utf8))
    }

    // MARK: - Daily summaries

    private struct DayBrief: Decodable {
        var brief: String
        var themes: [String]
    }

    static func dayBrief(dayName: String, sessions: String) async throws -> (brief: String, themes: [String]) {
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["brief", "themes"],
            "properties": [
                "brief": ["type": "string"],
                "themes": ["type": "array", "items": ["type": "string"]],
            ],
        ]
        let text = try await request(
            system: """
            You write a short end-of-day recap for a person with hearing loss who records their meetings, \
            conversations, lectures and voice notes. Write to them as "you", in 2 to 4 sentences: what the day \
            was about and the most important things to follow up on. themes are ideas or subjects that came up \
            more than once or stood out (empty if none). Never invent details.
            """,
            prompt: "Here is what was recorded on \(dayName), with each session's summary and actions:\n\n\(sessions)",
            schema: schema
        )
        let brief = try JSONDecoder().decode(DayBrief.self, from: Data(text.utf8))
        return (brief.brief, brief.themes)
    }

    // MARK: - API

    /// Sends one request and returns the JSON text of the reply, shaped by `schema`.
    private static func request(system: String, prompt: String, schema: [String: Any]) async throws -> String {
        guard let key = APIKeyStore.key else { throw Failure.badKey }
        let model = self.model

        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 16000,
            "system": system,
            "messages": [["role": "user", "content": prompt]],
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": schema],
            ],
        ]
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        if model != .haiku {
            // If a safety check declines the request, let the API retry it on a suitable model.
            body["fallbacks"] = "default"
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        switch status {
        case 200: break
        case 401, 403: throw Failure.badKey
        case 429, 529: throw Failure.rateLimited
        default:
            let message = (json["error"] as? [String: Any])?["message"] as? String
            throw Failure.server(message ?? "Claude returned an error (HTTP \(status)).")
        }
        if json["stop_reason"] as? String == "refusal" { throw Failure.refused }

        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.isEmpty else { throw Failure.empty }
        return text
    }
}

/// The Anthropic API key, kept in the Keychain (encrypted, on this device only).
enum APIKeyStore {
    private static let service = "LiveCaptions.anthropic"
    private static let account = "api-key"

    private static var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    static var key: String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        var query = baseQuery
        query[kSecValueData as String] = Data(key.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
