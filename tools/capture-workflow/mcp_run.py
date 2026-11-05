"""Runs a scenario against one cinnabar-mcp process, then exits.

    python -I mcp_run.py --repo <worktree> [--mcp <cinnabar-mcp>] [--shots <dir>] [--keep] scenario.json

A scenario is a JSON list of {"tool": ..., "args": {...}} steps. "$SHOTS" inside a string expands
to the shots directory. A step may add "expect_error": true, or "until_text": "<substring>" with an optional "timeout": <secs>
(default 30) to repeat the call until its reply contains that text, so a step can wait for state. The client is always quit at the end,
even when a step fails, unless --keep is given. --keep holds the session (and its local server) open until the client
window is closed, so run it in the background. Output is one line per step: ok/ERR, seconds, and the reply text.
"""
import argparse
import json
import os
import subprocess
import sys
import time

parser = argparse.ArgumentParser()
parser.add_argument("--repo", required=True)
parser.add_argument("--mcp", help="cinnabar-mcp binary (default: $CINNABAR_MCP, else <repo>/target/debug)")
parser.add_argument("--shots", default=os.path.join(os.environ.get("TEMP", "."), "cinnabar-shots"))
parser.add_argument("--keep", action="store_true", help="leave the client running afterwards")
parser.add_argument("scenario")
options = parser.parse_args()

repo = os.path.abspath(options.repo)
exe = ".exe" if os.name == "nt" else ""
mcp = (
    options.mcp
    or os.environ.get("CINNABAR_MCP")
    or os.path.join(repo, "target", "debug", f"cinnabar-mcp{exe}")
)
if not os.path.exists(mcp):
    sys.exit(
        f"cinnabar-mcp not found at {mcp}: build it with `cargo build -p cinnabar-mcp`, "
        "or pass --mcp / set CINNABAR_MCP"
    )
shots = options.shots.replace("\\", "/")
os.makedirs(shots, exist_ok=True)
steps = json.loads(open(options.scenario, encoding="utf8").read().replace("$SHOTS", shots))

proc = subprocess.Popen([mcp, "--repo", repo], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, cwd=repo, text=True, bufsize=1)
counter = 0


def rpc(method, params=None):
    global counter
    counter += 1
    message = {"jsonrpc": "2.0", "id": counter, "method": method}
    if params is not None:
        message["params"] = params
    proc.stdin.write(json.dumps(message) + "\n")
    proc.stdin.flush()
    while True:
        line = proc.stdout.readline()
        if not line:
            raise SystemExit("mcp closed")
        reply = json.loads(line)
        if reply.get("id") == counter:
            return reply


rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                   "clientInfo": {"name": "mcp_run", "version": "1"}})
failed = False
client_pid = None
try:
    for index, step in enumerate(steps):
        started = time.time()
        deadline = started + float(step.get("timeout", 30))
        while True:
            reply = rpc("tools/call", {"name": step["tool"], "arguments": step.get("args", {})})
            result = reply.get("result", reply.get("error"))
            is_error = bool(isinstance(result, dict) and result.get("isError")) or "error" in reply
            content = result.get("content", []) if isinstance(result, dict) else []
            text = " ".join(item.get("text", "") for item in content if item.get("type") == "text")
            text = text or json.dumps(result)
            wanted = step.get("until_text")
            if not wanted or wanted in text or is_error or time.time() > deadline:
                if wanted and wanted not in text:
                    is_error = True
                break
            time.sleep(0.25)
        if step["tool"] == "launch_client" and not is_error:
            client_pid = json.loads(text).get("pid")
        print(f"{index:02d} {step['tool']:<12} {'ERR' if is_error else 'ok '} "
              f"{time.time() - started:5.1f}s {text[:int(os.environ.get("MCP_RUN_WIDTH", "300"))]}", flush=True)
        if is_error != bool(step.get("expect_error")):
            failed = True
            break
finally:
    if options.keep and client_pid and not failed:
        print(f"client running (pid {client_pid}); close its window to end the session", flush=True)
        while subprocess.run(["tasklist", "/FI", f"PID eq {client_pid}", "/NH"],
                             capture_output=True, text=True).stdout.count(str(client_pid)):
            time.sleep(2)
    try:
        if not options.keep:
            rpc("tools/call", {"name": "quit", "arguments": {}})
    except BaseException:  # noqa: BLE001
        pass
    proc.stdin.close()
    try:
        proc.wait(timeout=20)
    except subprocess.TimeoutExpired:
        proc.kill()
sys.exit(1 if failed else 0)
