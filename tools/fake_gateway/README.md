# Fake Gateway — hermes-webui 契约测试模拟服务器

本地模拟 `hermes-webui`（:30002）的 HTTP/SSE API，用于客户端开发与契约测试。
端口 **30003**（避开真实 30002）。Python + FastAPI。

## 快速开始

```bash
cd tools/fake_gateway
pip install -r requirements.txt
python main.py            # 启动，监听 0.0.0.0:30003
```

启动后可以用 `smoke_test.py` 冒烟验证：

```bash
python smoke_test.py      # 输出 PASS/FAIL，全 PASS 即端点形状正确
```

## 已实现端点（对齐 docs/specs/api_spec.md）

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/auth/login` | 登录，返回 `{"ok": true}` |
| GET | `/api/sessions` | 会话列表（返回几个样例会话） |
| GET | `/api/sessions/{id}` | 单会话详情 |
| POST | `/api/chat/start` | 开始聊天，返回 `{"session_id": "..."}` |
| GET | `/api/chat/stream/{id}` | SSE 流式 chunk（模拟打字机效果） |
| GET | `/api/crons` | 定时任务列表 |
| GET | `/api/memory` | 记忆列表 |
| GET | `/api/skills` | 技能列表 |
| GET | `/api/workspaces` | 工作区列表 |
| POST | `/api/upload` | multipart 上传，回显文件名与大小 |
| GET | `/api/insights` | 用量统计 |
| GET | `/api/profiles` | Profile 列表 |
| POST | `/api/profiles/switch` | 切换 Profile |

## 契约测试思路

1. **形状校验**：对每个端点发请求，断言响应 JSON 的关键字段/类型（见 smoke_test.py）。
2. **SSE 校验**：消费 `/api/chat/stream/{id}`，断言收到多个 `data:` chunk 且含 `content` 字段。
3. **客户端联调**：把客户端服务器地址指向 `http://127.0.0.1:30003`，可验证
   登录→会话→聊天→上传全链路，与真实服务器行为一致。

> 注意：fake_gateway **不实现服务端逻辑**，只回放预置 JSON 形状，
> 用于验证客户端解析与 UI 渲染，不做端到端业务测试。