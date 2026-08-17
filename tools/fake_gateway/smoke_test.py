"""fake_gateway 冒烟测试 — 验证各端点形状正确。

用法:
    python smoke_test.py            # 自动起一个临时进程并测试
    python smoke_test.py --no-start # 假设 main.py 已在 30003 运行，只测
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time

import httpx

BASE = "http://127.0.0.1:30003"


def check(name: str, cond: bool, detail: str = "") -> None:
    status = "PASS" if cond else "FAIL"
    print(f"[{status}] {name}" + (f" — {detail}" if detail else ""))
    if not cond:
        raise SystemExit(1)


def main(no_start: bool = False) -> None:
    proc = None
    if not no_start:
        proc = subprocess.Popen(
            [sys.executable, "main.py"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        # 等待端口就绪
        for _ in range(40):
            try:
                httpx.get(f"{BASE}/api/health", timeout=0.5)
                break
            except Exception:
                time.sleep(0.25)
        else:
            print("FAIL: fake gateway 未在 5s 内就绪")
            proc.terminate()
            sys.exit(1)

    try:
        with httpx.Client(base_url=BASE, timeout=5.0) as client:
            # 1. 登录
            r = client.post("/api/auth/login", json={"password": "test"})
            check("POST /api/auth/login", r.status_code == 200 and r.json().get("ok"))

            # 2. 会话列表
            r = client.get("/api/sessions")
            data = r.json().get("data")
            check("GET /api/sessions", r.status_code == 200 and isinstance(data, list) and len(data) > 0)

            # 3. 会话详情
            sid = data[0]["id"]
            r = client.get(f"/api/sessions/{sid}")
            check("GET /api/sessions/{id}", r.status_code == 200 and r.json().get("data", {}).get("id") == sid)

            # 4. 开始聊天
            r = client.post("/api/chat/start", json={"session_id": sid})
            check("POST /api/chat/start", r.status_code == 200 and "session_id" in r.json().get("data", {}))

            # 5. SSE 流
            with client.stream("GET", f"/api/chat/stream/{sid}") as resp:
                chunks = [line for line in resp.iter_lines() if line.startswith("data: ")]
            check(
                "GET /api/chat/stream/{id} (SSE)",
                len(chunks) >= 2,
                f"收到 {len(chunks)} 个 data chunk",
            )

            # 6. crons
            r = client.get("/api/crons")
            check("GET /api/crons", r.status_code == 200 and isinstance(r.json().get("data"), list))

            # 7. memory / skills / workspaces
            for ep in ("/api/memory", "/api/skills", "/api/workspaces", "/api/profiles"):
                r = client.get(ep)
                check(f"GET {ep}", r.status_code == 200 and isinstance(r.json().get("data"), list))

            # 8. upload（multipart）
            files = {"file": ("test.txt", b"hello world", "text/plain")}
            r = client.post("/api/upload", files=files, data={"session_id": sid})
            up = r.json().get("data", {})
            check(
                "POST /api/upload",
                r.status_code == 200 and up.get("filename") == "test.txt" and up.get("size") == len(b"hello world"),
            )

            # 9. insights / profile switch
            r = client.get("/api/insights")
            check("GET /api/insights", r.status_code == 200 and "total_sessions" in r.json().get("data", {}))
            r = client.post("/api/profiles/switch", json={"profile": "research"})
            check("POST /api/profiles/switch", r.status_code == 200 and r.json().get("data", {}).get("current") == "research")

        print("\n全部 PASS — fake_gateway 端点形状正确。")
    finally:
        if proc is not None:
            proc.terminate()
            proc.wait(timeout=5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-start", action="store_true", help="假设已有实例在跑")
    args = parser.parse_args()
    main(no_start=args.no_start)