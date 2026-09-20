# 赛智荐

面向大学生团队的 AI 竞赛匹配与参赛规划 MVP。用户可以创建多个项目、粘贴文字或上传 Markdown 文档，系统会从本地赛氪比赛数据库中筛出仍可报名/即将开始的比赛，使用本地 `bge-small-zh-v1.5` + Qdrant 做语义召回，再使用用户自己的大模型额度生成推荐理由、资格提示、材料清单、时间计划和项目改进建议。

## 技术结构

- `frontend/`：Flutter Web 中文响应式界面
- `backend/`：FastAPI、LiteLLM、SQLAlchemy、Celery
- PostgreSQL：账号、项目、对话、模型配置和用量记录
- Redis：Celery 队列、任务锁和重试调度
- `saikr_competitions.db`：比赛数据；API 只读、Worker 定时更新
- Qdrant `localhost:6333`：512 维比赛语义向量
- `models/bge-small-zh-v1.5`：本地中文向量模型

模型供应商不写死。设置页可填写 LiteLLM 模型名、API 地址和用户自己的 API Key；API Key 经 Fernet 加密后保存在 PostgreSQL 中，前端读取配置时不会返回密钥明文。

## 首次运行

推荐使用 Docker Compose；Windows 可通过 Docker Desktop 的 WSL2 Linux 容器运行，正式环境使用 Linux。

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\setup.ps1
.\scripts\run-docker.ps1
```

Linux 服务器先安装 Docker、Docker Compose 与 Flutter，并完整拉取模型子模块；将现有
`saikr_competitions.db` 复制到项目根目录、配置 `.env` 后启动：

```bash
git submodule update --init --recursive
cp .env.example .env
# 编辑 .env，至少更换 JWT_SECRET、ENCRYPTION_KEY 与初始管理员密码
bash scripts/run-docker.sh
```

`run-docker.ps1` 和 `run-docker.sh` 都会先构建 Flutter Web，再构建并启动容器。

浏览器访问 <http://localhost:8000>。`setup.ps1` 会：

1. 生成不入库的 `.env`，包括随机密钥和首个管理员密码；
2. 启动 PostgreSQL、Redis 和 Qdrant；
3. 建立 Python 虚拟环境并安装依赖；
4. 将当前可报名/即将开始的比赛写入 Qdrant；
5. 构建 Flutter Web。

完整 Compose 栈包括 `api`、`worker`、`beat`、`redis`、`postgres` 和 `qdrant`。首次启动前应修改 `.env` 中的管理员密码；首次创建管理员后，后续重启不会覆盖密码。

数据库结构由 Alembic 迁移：

```powershell
.\.venv\Scripts\python.exe -m alembic -c alembic.ini upgrade head
```

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

## 后台定时爬虫

- 每天 `02:00`、`14:00`（北京时间）按最近更新顺序增量抓取；
- 连续 3 页无变化时停止，最多 50 页；
- 每周日 `03:00` 完整校准，成功后标记已下架赛事；
- 全量校准前在线备份 SQLite，保留最近 7 份；
- 抓取后自动增量同步或原子重建 Qdrant；
- 失败后分别在 15、60、180 分钟后重试；
- 管理员可在“任务管理”页面查看状态并手动触发。

查看后台日志：

```powershell
docker compose logs -f api worker beat
```

## 手动运行原始爬虫

原有采集方式仍保留：

```powershell
py saikr_crawler.py --init-only
py saikr_crawler.py
```

手动爬虫更新数据库后，可运行 `scripts\build-index.ps1` 原子重建推荐索引。
