# AgentBridge

For installed-app configuration, data isolation, read-only mode and complete examples, see the [MCP and CLI guide](../../Docs/agent/AGENT_INTERFACE.md). Release apps include the executable in `Contents/Helpers`; a source build is only needed for development.

This directory documents the boundary for tools that expose Manuscript Matrix commands to trusted AI agents.

The local CLI executable at `Packages/ManuscriptKit/Sources/ManuscriptAgentBridge` reads the same board file as the app and applies the same validated application commands. It also implements an MCP stdio server for trusted local AI clients.

The service must consume `Contracts/agent-command.schema.json` and invoke application commands. It must not edit the board JSON file.

```bash
make agent-help

# Read the board
swift run --disable-sandbox --package-path Packages/ManuscriptKit \
  manuscript-matrix-agent board

# Apply one JSON command from standard input
swift run --disable-sandbox --package-path Packages/ManuscriptKit \
  manuscript-matrix-agent apply < command.json

# Start the MCP stdio server
swift run --disable-sandbox --package-path Packages/ManuscriptKit \
  manuscript-matrix-agent mcp
```

The MCP process exposes read-only board tools plus one validated command tool. It has no network listener, and the application layer remains the sole write boundary.
