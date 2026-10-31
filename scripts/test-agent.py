#!/usr/bin/env python3
"""Exercise the shipped CLI/MCP boundary using only disposable explicit storage."""
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AGENT = ROOT / "build/release/DerivedData/Build/Products/Release/Manuscript Matrix.app/Contents/Helpers/manuscript-matrix-agent"


def run(*args, data=None, success=True):
    result = subprocess.run([str(AGENT), *args], input=data, text=True, capture_output=True, timeout=20)
    assert (result.returncode == 0) == success, result.stderr
    return result


def rpc(*args, requests):
    result = run(*args, "mcp", data="\n".join(json.dumps(x) for x in requests) + "\n")
    return [json.loads(line) for line in result.stdout.splitlines()]


def main():
    assert AGENT.is_file(), "Run make release-build first."
    (ROOT / "build").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="agent-test-", dir=ROOT / "build") as directory:
        board = Path(directory) / "isolated.json"
        assert json.loads(run("--board", str(board), "board").stdout)["manuscripts"] == []
        assert not board.exists(), "Read must not create a board."
        command = {"version": 1, "commandId": "aab278fa-b02a-4cd2-a0f1-329f21d74f75", "type": "manuscript.create", "payload": {"title": "Fictional integration example", "shortTitle": "Example"}, "source": "agent"}
        assert json.loads(run("--board", str(board), "apply", data=json.dumps(command)).stdout)["ok"]
        initial = board.read_bytes()
        assert len(json.loads(initial)["manuscripts"]) == 1
        run("--board", str(board), "--read-only", "apply", data=json.dumps(command), success=False)
        requests = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "unsupported-version"}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
            {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "matrix_command_apply", "arguments": {"type": "manuscript.create", "payload": {"title": "Denied", "shortTitle": "Denied"}}}},
            {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "matrix_board_get", "arguments": {}}},
        ]
        replies = rpc("--board", str(board), "--read-only", requests=requests)
        assert replies[0]["result"]["serverInfo"]["version"] == "0.9.1"
        assert replies[0]["result"]["protocolVersion"] == "2025-11-25"
        assert len(replies[1]["result"]["tools"]) == 3
        assert replies[2]["result"]["isError"]
        assert len(replies[3]["result"]["structuredContent"]["manuscripts"]) == 1
        assert board.read_bytes() == initial, "Denied writes changed storage."
        run("--demo", "--board", str(board), "board", success=False)
        run("--board", success=False)
        run("--demo", "path", success=False)
        assert len(json.loads(run("--demo", "board").stdout)["manuscripts"]) == 5
        demo = rpc("--demo", requests=[requests[1], requests[2], requests[3], requests[4]])
        assert len(demo[0]["result"]["tools"]) == 4
        assert not demo[1]["result"].get("isError", False)
        assert len(demo[2]["result"]["structuredContent"]["manuscripts"]) == 6
        assert len(json.loads(run("--demo", "board").stdout)["manuscripts"]) == 5
        assert board.read_bytes() == initial, "Demo changed explicit storage."
    print("CLI/MCP integration passed: explicit storage, read-only enforcement, demo isolation and clean EOF shutdown.")


if __name__ == "__main__":
    main()
