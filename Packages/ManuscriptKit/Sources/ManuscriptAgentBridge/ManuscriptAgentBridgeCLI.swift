import Foundation
import ManuscriptApplication
import ManuscriptDomain
import ManuscriptInfrastructure

private struct WireReceipt: Codable {
    let ok: Bool
    let commandId: UUID?
    let appliedAt: Date?
    let summary: String?
    let affectedEntityIds: [String]
    let error: String?
}

@main
struct ManuscriptAgentBridgeCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            var action: String?
            var boardPath: String?
            var demo = false
            var readOnly = false
            var index = 0
            while index < arguments.count {
                let argument = arguments[index]
                switch argument {
                case "--board":
                    index += 1
                    guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                        throw AgentCommandCodecError.malformedPayload("--board requires a file path.")
                    }
                    boardPath = arguments[index]
                case "--demo": demo = true
                case "--read-only": readOnly = true
                default:
                    guard action == nil else {
                        throw AgentCommandCodecError.malformedPayload("Unexpected argument: \(argument)")
                    }
                    action = argument
                }
                index += 1
            }
            guard !(demo && boardPath != nil) else {
                throw AgentCommandCodecError.malformedPayload("--demo and --board are mutually exclusive.")
            }
            let fileURL = boardPath.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
                ?? JSONBoardRepository.defaultFileURL()
            let repository: any BoardRepository = demo
                ? InMemoryBoardRepository(snapshot: DemoBoardFactory.make())
                : JSONBoardRepository(fileURL: fileURL)
            let selectedAction = action ?? "help"
            switch selectedAction {
            case "board":
                let snapshot = try await repository.load()
                try writeJSON(snapshot)

            case "path":
                guard !demo else {
                    throw AgentCommandCodecError.malformedPayload("An in-memory demo has no board file.")
                }
                FileHandle.standardOutput.write(Data((fileURL.path + "\n").utf8))

            case "apply":
                guard !readOnly else {
                    throw AgentCommandCodecError.malformedPayload("Writes are disabled by --read-only.")
                }
                let data = FileHandle.standardInput.readDataToEndOfFile()
                guard !data.isEmpty else {
                    throw AgentCommandCodecError.malformedPayload("Expected one command envelope on stdin.")
                }
                let envelope = try AgentCommandCodec.decodeEnvelope(from: data)
                let command = try AgentCommandCodec.command(from: envelope)
                let mutation = try await BoardMutationExecutor.execute(
                    command,
                    repository: repository
                )
                try writeJSON(
                    WireReceipt(
                        ok: true,
                        commandId: envelope.commandID,
                        appliedAt: mutation.receipt.appliedAt,
                        summary: mutation.receipt.summary,
                        affectedEntityIds: mutation.receipt.affectedEntityIDs,
                        error: nil
                    )
                )

            case "mcp":
                await MatrixMCPServer(repository: repository, readOnly: readOnly).run()

            case "help", "--help", "-h":
                printHelp()

            default:
                throw AgentCommandCodecError.unsupportedCommand(selectedAction)
            }
        } catch {
            let receipt = WireReceipt(
                ok: false,
                commandId: nil,
                appliedAt: nil,
                summary: nil,
                affectedEntityIds: [],
                error: error.localizedDescription
            )
            try? writeJSON(receipt, toStandardError: true)
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func writeJSON<T: Encodable>(
        _ value: T,
        toStandardError: Bool = false
    ) throws {
        let encoder = AgentCommandCodec.makeEncoder(prettyPrinted: true)
        var data = try encoder.encode(value)
        data.append(0x0A)
        let handle = toStandardError ? FileHandle.standardError : FileHandle.standardOutput
        handle.write(data)
    }

    private static func printHelp() {
        print(
            """
            manuscript-matrix-agent

            Usage:
              manuscript-matrix-agent [--board FILE | --demo] [--read-only] COMMAND

              manuscript-matrix-agent board    Print the complete local board as JSON.
              manuscript-matrix-agent path     Print the shared local board file path.
              manuscript-matrix-agent apply    Read one v1 command envelope from stdin and apply it.
              manuscript-matrix-agent mcp      Run a newline-delimited MCP server over stdio.
              manuscript-matrix-agent help     Show this help.

            Options:
              --board FILE   Use an explicit JSON file instead of the personal board.
              --demo         Use fictional in-memory data; discard changes on exit.
              --read-only    Disable CLI writes and the MCP mutation tool.

            Mutations are validated by the same BoardReducer used by the macOS UI.
            See Contracts/agent-command.schema.json and Docs/agent/AGENT_INTERFACE.md.
            """
        )
    }
}
