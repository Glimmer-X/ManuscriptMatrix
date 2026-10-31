import Foundation
import ManuscriptApplication
import ManuscriptDomain

struct MatrixMCPServer {
    private let repository: any BoardRepository
    private let readOnly: Bool

    init(repository: any BoardRepository, readOnly: Bool = false) {
        self.repository = repository
        self.readOnly = readOnly
    }

    func run() async {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            do {
                let request = try AgentCommandCodec.makeDecoder().decode(
                    RPCRequest.self,
                    from: Data(line.utf8)
                )
                if request.method.hasPrefix("notifications/") { continue }
                guard let id = request.id else { continue }
                let result = try await handle(request)
                try write(RPCResponse(id: id, result: result, error: nil))
            } catch {
                let id = (try? AgentCommandCodec.makeDecoder().decode(
                    RPCRequest.self,
                    from: Data(line.utf8)
                ).id) ?? .null
                try? write(
                    RPCResponse(
                        id: id,
                        result: nil,
                        error: RPCError(code: -32603, message: error.localizedDescription)
                    )
                )
            }
        }
    }

    private func handle(_ request: RPCRequest) async throws -> JSONValue {
        switch request.method {
        case "initialize":
            return .object([
                "protocolVersion": .string("2025-11-25"),
                "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
                "serverInfo": .object([
                    "name": .string("manuscript-matrix"),
                    "title": .string("Manuscript Matrix"),
                    "version": .string("0.9.1")
                ]),
                "instructions": .string("Read the board before mutating it. Use stable UUIDs from matrix_board_get and apply one validated command at a time.")
            ])

        case "ping":
            return .object([:])

        case "server/discover":
            return .object([
                "serverInfo": .object(["name": .string("manuscript-matrix"), "version": .string("0.9.1")]),
                "capabilities": .object(["tools": .bool(true)])
            ])

        case "tools/list":
            return .object(["tools": .array(readOnly ? Array(Self.tools.prefix(3)) : Self.tools)])

        case "tools/call":
            guard let rawParams = request.params else {
                throw MCPBridgeError.invalidArguments("tools/call params are required")
            }
            let params = try rawParams.requireObject("tools/call params")
            let name = try params.requireString("name")
            let arguments = params["arguments"]?.objectValue ?? [:]
            return try await callTool(name: name, arguments: arguments)

        default:
            throw MCPBridgeError.unsupportedMethod(request.method)
        }
    }

    private func callTool(name: String, arguments: [String: JSONValue]) async throws -> JSONValue {
        do {
            let structured: JSONValue
            switch name {
            case "matrix_board_get":
                structured = try await encodedValue(repository.load())

            case "matrix_board_summary":
                let board = try await repository.load()
                structured = summary(for: board)

            case "matrix_command_catalog":
                structured = Self.commandCatalog

            case "matrix_command_apply":
                guard !readOnly else {
                    throw MCPBridgeError.invalidArguments("This server was started with --read-only.")
                }
                structured = try await apply(arguments: arguments)

            default:
                throw MCPBridgeError.unknownTool(name)
            }
            return toolResult(structured)
        } catch {
            return toolResult(
                .object(["ok": .bool(false), "error": .string(error.localizedDescription)]),
                isError: true
            )
        }
    }

    private func apply(arguments: [String: JSONValue]) async throws -> JSONValue {
        let type = try arguments.requireString("type")
        guard let payload = arguments["payload"] else {
            throw MCPBridgeError.invalidArguments("payload is required")
        }
        guard case .object = payload else {
            throw MCPBridgeError.invalidArguments("payload must be an object")
        }

        let commandID: UUID
        if let rawID = arguments["commandId"]?.stringValue {
            guard let parsed = UUID(uuidString: rawID) else {
                throw MCPBridgeError.invalidArguments("commandId must be a UUID")
            }
            commandID = parsed
        } else {
            commandID = UUID()
        }

        let requestedAt: Date?
        if let rawDate = arguments["requestedAt"]?.stringValue {
            requestedAt = ISO8601DateFormatter().date(from: rawDate)
            guard requestedAt != nil else {
                throw MCPBridgeError.invalidArguments("requestedAt must be ISO 8601")
            }
        } else {
            requestedAt = nil
        }

        let envelope = AgentCommandEnvelope(
            commandID: commandID,
            type: type,
            payload: payload,
            requestedAt: requestedAt,
            source: "agent"
        )
        let command = try AgentCommandCodec.command(from: envelope)
        let mutation = try await BoardMutationExecutor.execute(
            command,
            repository: repository
        )

        return .object([
            "ok": .bool(true),
            "commandId": .string(commandID.uuidString),
            "appliedAt": .string(ISO8601DateFormatter().string(from: mutation.receipt.appliedAt)),
            "summary": .string(mutation.receipt.summary),
            "affectedEntityIds": .array(mutation.receipt.affectedEntityIDs.map(JSONValue.string)),
            "boardModifiedAt": .string(ISO8601DateFormatter().string(from: mutation.board.modifiedAt))
        ])
    }

    private func summary(for board: BoardSnapshot) -> JSONValue {
        let manuscripts = board.visibleManuscripts.enumerated().map { index, manuscript -> JSONValue in
            let projection = board.manuscriptProjection(for: manuscript.id)
            var fields: [String: JSONValue] = [
                "id": .string(manuscript.id.description),
                "shortTitle": .string(manuscript.shortTitle),
                "title": .string(manuscript.title),
                "position": .number(Double(index + 1)),
                "status": .string(projection.status.rawValue),
                "readiness": .string(manuscript.readiness.rawValue),
                "readinessUpdatedAt": .string(ISO8601DateFormatter().string(from: manuscript.readinessUpdatedAt)),
                "targetCount": .number(Double(board.targets(for: manuscript.id).count))
            ]
            if let journalID = projection.activeJournalID {
                fields["activeJournalId"] = .string(journalID.description)
            }
            if let startedAt = projection.liveStartedAt {
                fields["liveStartedAt"] = .string(ISO8601DateFormatter().string(from: startedAt))
                fields["elapsedDays"] = .number(Double(startedAt.wholeDays(to: .now)))
            }
            return .object(fields)
        }

        return .object([
            "schemaVersion": .number(Double(board.schemaVersion)),
            "modifiedAt": .string(ISO8601DateFormatter().string(from: board.modifiedAt)),
            "journalCount": .number(Double(board.rankedJournals.count)),
            "manuscriptCount": .number(Double(board.visibleManuscripts.count)),
            "relationshipCount": .number(Double(board.relationships.count)),
            "manuscripts": .array(manuscripts)
        ])
    }

    private func toolResult(_ value: JSONValue, isError: Bool = false) -> JSONValue {
        let text = (try? compactJSON(value)) ?? "{}"
        return .object([
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            "structuredContent": value,
            "isError": .bool(isError)
        ])
    }

    private func compactJSON(_ value: JSONValue) throws -> String {
        let data = try AgentCommandCodec.makeEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private func encodedValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try AgentCommandCodec.makeEncoder().encode(value)
        return try AgentCommandCodec.makeDecoder().decode(JSONValue.self, from: data)
    }

    private func write<T: Encodable>(_ value: T) throws {
        var data = try AgentCommandCodec.makeEncoder().encode(value)
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }

    private static let tools: [JSONValue] = [
        .object([
            "name": .string("matrix_board_get"),
            "title": .string("Get manuscript board"),
            "description": .string("Return the complete local board, including stable IDs, journals, manuscripts, targets, relationships, and the immutable submission-event audit trail."),
            "inputSchema": .object(["type": .string("object"), "properties": .object([:]), "additionalProperties": .bool(false)]),
            "annotations": .object(["readOnlyHint": .bool(true), "idempotentHint": .bool(true)])
        ]),
        .object([
            "name": .string("matrix_board_summary"),
            "title": .string("Summarize manuscript board"),
            "description": .string("Return compact manuscript statuses, live elapsed days, targets, and portfolio counts."),
            "inputSchema": .object(["type": .string("object"), "properties": .object([:]), "additionalProperties": .bool(false)]),
            "annotations": .object(["readOnlyHint": .bool(true), "idempotentHint": .bool(true)])
        ]),
        .object([
            "name": .string("matrix_command_catalog"),
            "title": .string("List all board operations"),
            "description": .string("Return every supported read/write command and its required payload fields, including full manuscript and journal CRUD, ranking, metrics, multi-system partitions, submissions, targets, relationships, and history correction."),
            "inputSchema": .object(["type": .string("object"), "properties": .object([:]), "additionalProperties": .bool(false)]),
            "annotations": .object(["readOnlyHint": .bool(true), "idempotentHint": .bool(true)])
        ]),
        .object([
            "name": .string("matrix_command_apply"),
            "title": .string("Apply a board command"),
            "description": .string("Apply one version-1 Manuscript Matrix command through the same validation and persistence layer as the UI. Read the board first and use stable UUIDs."),
            "inputSchema": .object([
                "type": .string("object"),
                "required": .array([.string("type"), .string("payload")]),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "type": .object([
                        "type": .string("string"),
                        "enum": .array(MatrixMCPServer.commandTypes.map(JSONValue.string))
                    ]),
                    "payload": .object(["type": .string("object")]),
                    "commandId": .object(["type": .string("string"), "format": .string("uuid")]),
                    "requestedAt": .object(["type": .string("string"), "format": .string("date-time")])
                ])
            ]),
            "annotations": .object(["readOnlyHint": .bool(false), "idempotentHint": .bool(false)])
        ])
    ]

    private static let commandTypes = [
        "manuscript.create", "manuscript.update", "manuscript.position.set", "manuscript.readiness.set", "manuscript.archive.set", "manuscript.delete",
        "journal.create", "journal.rename", "journal.rank.set", "journal.metadata.update", "journal.archive.set", "journal.delete",
        "target.set", "target.remove", "submission.record", "submission.status.record", "submission.event.amend", "submission.event.void",
        "relationship.create", "relationship.update", "relationship.remove"
    ]

    private static let commandCatalog: JSONValue = .object([
        "partitionShape": .object([
            "id": .string("optional UUID"),
            "scheme": .string("required enum: JCR, CCF, CAS, or 新锐"),
            "year": .string("optional integer, e.g. 2024 or 2025"),
            "value": .string("required finite value: JCR Q1–Q4; CCF A–C; CAS/新锐 1区–4区"),
            "category": .string("optional subject category")
        ]),
        "commands": .array([
            catalog("manuscript.create", ["title", "shortTitle"], ["id", "tags", "readiness", "createdAt"], "Create a manuscript; readiness is incomplete, experimenting, conceptualizing, writing, or readyToSubmit and defaults to incomplete."),
            catalog("manuscript.update", ["manuscriptId", "title", "shortTitle"], ["tags"], "Replace all editable manuscript metadata."),
            catalog("manuscript.position.set", ["manuscriptId", "position"], [], "Move a manuscript column and normalize all visible manuscript positions."),
            catalog("manuscript.readiness.set", ["manuscriptId", "readiness"], ["occurredAt"], "Set the preparation stage to incomplete, experimenting, conceptualizing, writing, or readyToSubmit without changing submission history."),
            catalog("manuscript.archive.set", ["manuscriptId", "archived"], ["occurredAt"], "Archive or restore a manuscript."),
            catalog("manuscript.delete", ["manuscriptId", "confirmPermanentDeletion"], [], "Permanently delete the manuscript and all related board records; confirmation must be true."),
            catalog("journal.create", ["name", "rank"], ["id", "impactFactor", "category", "averageDecisionDays", "partitions", "issn", "eISSN", "tags", "createdAt"], "Create a journal with complete metadata. Use partitions rather than the legacy quartile field."),
            catalog("journal.rename", ["journalId", "newName"], ["occurredAt"], "Rename while preserving historical name snapshots."),
            catalog("journal.rank.set", ["journalId", "rank"], [], "Move the journal and normalize the ladder."),
            catalog("journal.metadata.update", ["journalId"], ["impactFactor", "category", "averageDecisionDays", "partitions", "issn", "eISSN", "tags"], "Replace all editable journal metadata. Partition schemes and values are finite enums."),
            catalog("journal.archive.set", ["journalId", "archived"], ["occurredAt"], "Archive or restore a journal."),
            catalog("journal.delete", ["journalId", "confirmPermanentDeletion"], [], "Permanently delete the journal and related target/submission records; confirmation must be true."),
            catalog("target.set", ["manuscriptId", "journalId", "priority"], ["note"], "Insert or move a target and normalize priorities."),
            catalog("target.remove", ["manuscriptId", "journalId"], [], "Remove a planned target."),
            catalog("submission.record", ["manuscriptId", "journalId"], ["occurredAt", "note"], "Record a real submission."),
            catalog("submission.status.record", ["manuscriptId", "journalId", "status"], ["occurredAt", "note"], "Record resubmitted, majorRevision, minorRevision, rejectAndResubmit, rejected, accepted, or withdrawn."),
            catalog("submission.event.void", ["eventId", "reason"], ["occurredAt"], "Correct an event without deleting its audit trace."),
            catalog("submission.event.amend", ["eventId", "occurredAt", "reason"], ["note", "amendedAt"], "Correct an event date or note while preserving its prior values in the audit trace."),
            catalog("relationship.create", ["firstManuscriptId", "secondManuscriptId", "statement"], ["id", "direction", "createdAt"], "Create one shared manuscript relationship."),
            catalog("relationship.update", ["relationshipId", "direction", "statement"], [], "Update relationship direction and statement."),
            catalog("relationship.remove", ["relationshipId"], [], "Remove a relationship.")
        ])
    ])

    private static func catalog(
        _ type: String,
        _ required: [String],
        _ optional: [String],
        _ description: String
    ) -> JSONValue {
        .object([
            "type": .string(type),
            "required": .array(required.map(JSONValue.string)),
            "optional": .array(optional.map(JSONValue.string)),
            "description": .string(description)
        ])
    }
}

private struct RPCRequest: Decodable {
    let jsonrpc: String?
    let id: JSONValue?
    let method: String
    let params: JSONValue?

    var requestedProtocolVersion: String? {
        params?.objectValue?["protocolVersion"]?.stringValue
    }
}

private struct RPCResponse: Encodable {
    let jsonrpc = "2.0"
    let id: JSONValue
    let result: JSONValue?
    let error: RPCError?
}

private struct RPCError: Encodable {
    let code: Int
    let message: String
}

private enum MCPBridgeError: LocalizedError {
    case unsupportedMethod(String)
    case unknownTool(String)
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedMethod(method): "Unsupported JSON-RPC method: \(method)."
        case let .unknownTool(name): "Unknown MCP tool: \(name)."
        case let .invalidArguments(reason): "Invalid MCP arguments: \(reason)."
        }
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    func requireObject(_ label: String) throws -> [String: JSONValue] {
        guard let value = objectValue else {
            throw MCPBridgeError.invalidArguments("\(label) must be an object")
        }
        return value
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func requireString(_ key: String) throws -> String {
        guard let value = self[key]?.stringValue else {
            throw MCPBridgeError.invalidArguments("\(key) is required and must be a string")
        }
        return value
    }
}
