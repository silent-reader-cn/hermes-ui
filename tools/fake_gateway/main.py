"""Fake hermes-webui gateway — 契约测试模拟服务器。

监听 0.0.0.0:30003，模拟 hermes-webui (:30002) 的核心 HTTP + SSE 端点。
用于客户端开发联调与契约冒烟，不实现任何服务端业务逻辑。

用法:
    python main.py            # 启动
    python smoke_test.py      # 冒烟验证（脚本内起进程）
"""
from __future__ import annotations

import asyncio
import json
import os
import time
import uuid
from typing import Any

from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse

app = FastAPI(title="fake-hermes-gateway", version="0.1.0")

API = "/api"

# ---------------- 预置样例数据 ----------------

SAMPLE_SESSIONS = [
    {
        "id": "sess-0001",
        "title": "示例会话：连接测试",
        "created_at": "2026-08-16T10:00:00Z",
        "updated_at": "2026-08-16T10:05:00Z",
        "is_pinned": False,
        "is_archived": False,
        "messages_count": 3,
    },
    {
        "id": "sess-0002",
        "title": "示例会话：Kanban 调研",
        "created_at": "2026-08-15T09:00:00Z",
        "updated_at": "2026-08-15T12:00:00Z",
        "is_pinned": True,
        "is_archived": False,
        "messages_count": 12,
    },
]

SAMPLE_CRONS = [
    {
        "id": "cron-0001",
        "name": "每日备份",
        "schedule": "0 9 * * *",
        "enabled": True,
        "status": "running",
    },
    {
        "id": "cron-0002",
        "name": "周报生成",
        "schedule": "0 18 * * 5",
        "enabled": False,
        "status": "paused",
    },
]

SAMPLE_MEMORY = [
    {"id": "mem-1", "content": "用户偏好极简灰白 UI。", "zone": "笔记"},
    {"id": "mem-2", "content": "项目使用 Flutter + Cupertino。", "zone": "画像"},
]

SAMPLE_SKILLS = [
    {"name": "hermes-ui-codebase", "description": "调试 hermes-ui 客户端。", "category": "开发"},
    {"name": "clash-verge-control", "description": "操作 Clash 代理。", "category": "网络"},
]

SAMPLE_WORKSPACES = [
    {"path": "/workspace/demo", "name": "demo", "is_active": True},
    {"path": "/workspace/project", "name": "project", "is_active": False},
]

SAMPLE_INSIGHTS = {
    "total_sessions": 12,
    "total_messages": 456,
    "total_tokens": 123456,
    "total_cost_usd": 1.23,
    "by_model": [{"model": "deepseek-v4-flash", "messages": 300, "tokens": 80000}],
    "daily": [
        {"date": "2026-08-03", "tokens": 1000},
        {"date": "2026-08-04", "tokens": 2000},
    ],
}

SAMPLE_PROFILES = [
    {"name": "default", "label": "默认"},
    {"name": "research", "label": "研究"},
    {"name": "gaming", "label": "游戏"},
]


def _json(obj: Any) -> dict:
    return {"ok": True, "data": obj}


# ---------------- 端点 ----------------

@app.post(f"{API}/auth/login")
async def auth_login(request: Request):
    body = await request.json()
    # 密码非空即可（不校验内容，模拟成功登录）
    if not body.get("password"):
        return {"ok": False, "error": "password required"}
    return {"ok": True}


@app.get(f"{API}/sessions")
async def sessions():
    return _json(SAMPLE_SESSIONS)


@app.get(f"{API}/sessions/{{session_id}}")
async def session_detail(session_id: str):
    for s in SAMPLE_SESSIONS:
        if s["id"] == session_id:
            return _json(s)
    return {"ok": False, "error": "not found"}


@app.post(f"{API}/chat/start")
async def chat_start(request: Request):
    body = await request.json()
    session_id = body.get("session_id") or f"sess-{uuid.uuid4().hex[:8]}"
    return _json({"session_id": session_id, "message": "started"})


@app.get(f"{API}/chat/stream/{{session_id}}")
async def chat_stream(session_id: str):
    """SSE 流式模拟：每 50ms 发一个 content chunk，共 5 个。"""

    async def gen():
        for i in range(1, 6):
            chunk = {"type": "content", "content": f"chunk {i} ", "session_id": session_id}
            yield f"data: {json.dumps(chunk, ensure_ascii=False)}\n\n"
            await asyncio.sleep(0.05)
        done = {"type": "done", "session_id": session_id}
        yield f"data: {json.dumps(done, ensure_ascii=False)}\n\n"

    return StreamingResponse(gen(), media_type="text/event-stream")


@app.get(f"{API}/crons")
async def crons():
    return _json(SAMPLE_CRONS)


@app.get(f"{API}/memory")
async def memory():
    return _json(SAMPLE_MEMORY)


@app.get(f"{API}/skills")
async def skills():
    return _json(SAMPLE_SKILLS)


@app.get(f"{API}/workspaces")
async def workspaces():
    return _json(SAMPLE_WORKSPACES)


@app.post(f"{API}/upload")
async def upload(request: Request):
    form = await request.form()
    file = form.get("file")
    session_id = form.get("session_id")
    if file is None:
        return {"ok": False, "error": "file missing"}
    return _json(
        {
            "filename": file.filename,
            "size": len(await file.read()) if hasattr(file, "read") else 0,
            "session_id": session_id,
        }
    )


@app.post(f"{API}/file/delete")
async def file_delete(request: Request):
    body = await request.json()
    if not body.get("session_id") or not body.get("path"):
        return {"ok": False, "error": "session_id and path required"}
    return {"ok": True, "path": body["path"]}


@app.post(f"{API}/file/rename")
async def file_rename(request: Request):
    body = await request.json()
    if not body.get("session_id") or not body.get("path") or not body.get("new_name"):
        return {"ok": False, "error": "session_id, path and new_name required"}
    return {"ok": True, "old_path": body["path"], "new_path": body["new_name"]}


@app.get(f"{API}/insights")
async def insights():
    return _json(SAMPLE_INSIGHTS)


@app.get(f"{API}/profiles")
async def profiles():
    return _json(SAMPLE_PROFILES)


@app.post(f"{API}/profiles/switch")
async def switch_profile(request: Request):
    body = await request.json()
    return _json({"current": body.get("profile", "default")})


@app.get(f"{API}/health")
async def health():
    return {"ok": True, "time": time.time()}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        app,
        host="0.0.0.0",
        port=int(os.environ.get("FAKE_GATEWAY_PORT", "30003")),
        log_level="info",
    )