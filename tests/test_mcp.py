"""Kiểm tra nhanh MCP server qua stdio — chỉ gọi các công cụ chỉ-đọc, không mở app hay bấm phím.

    python tests/test_mcp.py
"""

import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER = os.path.join(ROOT, "mcp", "touch_launcher_mcp.py")

MESSAGES = [
    {"jsonrpc": "2.0", "id": 1, "method": "initialize",
     "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "test", "version": "1"}}},
    {"jsonrpc": "2.0", "method": "notifications/initialized"},
    {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
    {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "list_apps", "arguments": {}}},
    {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "get_status", "arguments": {}}},
    {"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {"name": "open_app", "arguments": {"name": "khong-co-app-nay"}}},
    {"jsonrpc": "2.0", "id": 6, "method": "khong/ton-tai"},
]


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    payload = "".join(json.dumps(m, ensure_ascii=False) + "\n" for m in MESSAGES)
    proc = subprocess.run([sys.executable, "-I", SERVER], input=payload.encode("utf-8"),
                          capture_output=True, timeout=60)
    replies = {r["id"]: r for r in (json.loads(l) for l in proc.stdout.decode("utf-8").splitlines() if l.strip())}

    def check(cond, msg):
        if not cond:
            print("LỖI:", msg)
            print(proc.stderr.decode("utf-8", "replace"))
            sys.exit(1)

    check(replies.get(1, {}).get("result", {}).get("serverInfo", {}).get("name") == "touch-launcher", "initialize")
    tools = [t["name"] for t in replies.get(2, {}).get("result", {}).get("tools", [])]
    check({"list_apps", "open_app", "search", "media", "get_status"} <= set(tools), f"tools/list thiếu công cụ: {tools}")
    check(not replies[3]["result"]["isError"] and "YouTube" in replies[3]["result"]["content"][0]["text"], "list_apps")
    check(not replies[4]["result"]["isError"], "get_status")
    check(replies[5]["result"]["isError"], "open_app với tên sai phải trả về lỗi")
    check(replies[6].get("error", {}).get("code") == -32601, "method lạ phải trả về -32601")
    check(len(replies) == 6, f"số phản hồi sai: {len(replies)} (thông báo không được trả lời)")
    print(f"OK: MCP server trả lời đúng, {len(tools)} công cụ.")


if __name__ == "__main__":
    main()
