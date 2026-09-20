# 赛智荐

面向大学生团队的 AI 竞赛匹配与参赛规划 MVP。用户可以创建多个项目、粘贴文字或上传 Markdown 文档，系统会从本地赛氪比赛数据库中筛出仍可报名/即将开始的比赛，使用本地 `bge-small-zh-v1.5` + Qdrant 做语义召回，再使用用户自己的大模型额度生成推荐理由、资格提示、材料清单、时间计划和项目改进建议。

## 技术结构

- `frontend/`：Flutter Web 中文响应式界面
- `backend/`：FastAPI、LiteLLM、SQLAlchemy
- PostgreSQL：账号、项目、对话、模型配置和用量记录
- `saikr_competitions.db`：现有比赛数据，只读访问
- Qdrant `localhost:6333`：512 维比赛语义向量
- `models/bge-small-zh-v1.5`：本地中文向量模型

模型供应商不写死。设置页可填写 LiteLLM 模型名、API 地址和用户自己的 API Key；API Key 经 Fernet 加密后保存在 PostgreSQL 中，前端读取配置时不会返回密钥明文。

## 首次运行

要求：Windows PowerShell、Python 3.11、Docker Desktop，以及已经运行在 `6333` 端口的 Qdrant。

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\setup.ps1
.\scripts\run.ps1
```

浏览器访问 <http://localhost:8000>。`setup.ps1` 会：

1. 生成不入库的 `.env`，其中包含随机登录签名密钥与 API Key 加密密钥；
2. 启动 PostgreSQL；
3. 建立 Python 虚拟环境并安装依赖；
4. 将当前可报名/即将开始的比赛写入 Qdrant；
5. 构建 Flutter Web。

仅重新建立比赛向量索引：

```powershell
.\scripts\build-index.ps1
```

## 模型配置示例

| 供应商 | LiteLLM 模型名示例 | API 地址 |
| --- | --- | --- |
| OpenAI | `openai/gpt-5-mini` | 留空 |
| DeepSeek | `deepseek/deepseek-chat` | 留空 |
| 通义千问 | `dashscope/qwen-plus` | 留空 |
| Anthropic | `anthropic/claude-sonnet-4-5` | 留空 |
| Gemini | `gemini/gemini-2.5-flash` | 留空 |
| Ollama | `ollama/qwen3` | `http://localhost:11434` |
| OpenAI 兼容服务 | `openai/服务端模型名` | 填服务商的 `/v1` 地址 |

## IPv6 与安全

后端默认监听 `::`，因此在 Windows 防火墙放行 TCP 8000 后可通过 IPv6 访问。但当前没有域名和可信证书，公网 HTTP 会明文传输密码和 API Key。正式对外开放前必须配置域名 AAAA 记录与 HTTPS；在此之前建议只在本机或可信局域网测试，并使用测试 API Key。

## 原始爬虫

原有采集方式仍保留：

```powershell
py saikr_crawler.py --init-only
py saikr_crawler.py
```

爬虫更新数据库后，再运行 `scripts\build-index.ps1` 刷新推荐索引。

