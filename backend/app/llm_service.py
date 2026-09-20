from __future__ import annotations

import json
import re
import time
import uuid
from dataclasses import dataclass
from typing import Any

from litellm import acompletion
from sqlalchemy.orm import Session

from .models import ModelConfig, Project, UsageRecord
from .security import decrypt_secret


@dataclass
class LLMResult:
    text: str
    usage: Any
    request_id: str
    latency_ms: int


def project_context(project: Project) -> str:
    return f"""项目名称：{project.title}
项目简介：{project.description}
项目文档：{project.markdown_content[:24000]}
团队信息：学校={project.school or '未填写'}；学历={project.education_level or '未填写'}；年级={project.grade or '未填写'}；专业={project.major or '未填写'}；地区={project.region or '未填写'}；人数={project.team_size}；每周可投入={project.weekly_hours}小时"""


def _json_from_text(text: str) -> dict:
    cleaned = text.strip()
    fenced = re.search(r"```(?:json)?\s*(\{.*\})\s*```", cleaned, re.DOTALL)
    if fenced:
        cleaned = fenced.group(1)
    try:
        value = json.loads(cleaned)
    except json.JSONDecodeError:
        start, end = cleaned.find("{"), cleaned.rfind("}")
        if start < 0 or end <= start:
            raise ValueError("模型没有返回可解析的 JSON")
        value = json.loads(cleaned[start : end + 1])
    if not isinstance(value, dict):
        raise ValueError("模型返回结构不是 JSON 对象")
    return value


class LLMService:
    def __init__(self, db: Session, user_id: int, project_id: int | None = None) -> None:
        self.db = db
        self.user_id = user_id
        self.project_id = project_id
        self.config = db.query(ModelConfig).filter(ModelConfig.user_id == user_id).one_or_none()
        if not self.config:
            raise ValueError("请先在设置中配置 AI 模型")

    async def complete(self, messages: list[dict], operation: str, json_mode: bool = False) -> LLMResult:
        request_id = uuid.uuid4().hex
        started = time.perf_counter()
        api_key = decrypt_secret(self.config.encrypted_api_key)
        kwargs: dict[str, Any] = {
            "model": self.config.model_name,
            "messages": messages,
            "temperature": 0.25,
            "timeout": 120,
        }
        if api_key:
            kwargs["api_key"] = api_key
        if self.config.api_base:
            kwargs["api_base"] = self.config.api_base
        if json_mode:
            kwargs["response_format"] = {"type": "json_object"}
        try:
            response = await acompletion(**kwargs)
            latency_ms = int((time.perf_counter() - started) * 1000)
            text = response.choices[0].message.content or ""
            usage = getattr(response, "usage", None)
            self._record(request_id, operation, usage, latency_ms, True, None)
            return LLMResult(text=text, usage=usage, request_id=request_id, latency_ms=latency_ms)
        except Exception as exc:
            latency_ms = int((time.perf_counter() - started) * 1000)
            self._record(request_id, operation, None, latency_ms, False, type(exc).__name__)
            raise

    async def test(self) -> str:
        if self.config.provider == "demo":
            return "演示连接成功"
        result = await self.complete(
            [{"role": "user", "content": "只回复：连接成功"}], "connection_test"
        )
        return result.text.strip()

    async def recommend(self, project: Project, candidates: list[dict]) -> dict:
        if self.config.provider == "demo":
            self._record(uuid.uuid4().hex, "recommendation", None, 1, True, None)
            return {
                "summary": f"已从当前赛事中为“{project.title}”筛出方向最接近的比赛。正式使用时请在模型设置中换成你的真实模型。",
                "project_strengths": ["项目目标明确", "具备进一步包装为竞赛作品的基础"],
                "project_gaps": ["需要补充可量化的验证结果", "需要进一步核对各赛事参赛资格"],
                "matches": [
                    {
                        "contest_id": item["contest_id"],
                        "match_score": max(70, 92 - index * 6),
                        "why_match": f"赛事主题与项目描述存在较高语义相关性，可围绕“{project.description[:36] or project.title}”整理创新点与应用价值。",
                        "eligibility": "演示模式未调用大模型，请打开赛事官网核对学历、地区和团队人数要求。",
                        "deadline_note": "请以官网最新通知为准。",
                        "preparation": ["提炼问题、方案和创新点", "补充原型截图与测试数据", "按赛事模板准备申报材料"],
                    }
                    for index, item in enumerate(candidates[:3])
                ],
                "material_checklist": ["项目申报书", "核心功能演示材料", "团队分工说明", "测试结果与用户反馈"],
                "timeline": [
                    {"phase": "项目梳理", "date_range": "第 1 周", "tasks": ["明确赛道", "提炼创新点"]},
                    {"phase": "证据补强", "date_range": "第 2–3 周", "tasks": ["完成测试", "整理数据"]},
                    {"phase": "材料定稿", "date_range": "提交前", "tasks": ["核对规则", "模拟答辩"]},
                ],
                "improvement_suggestions": ["用对照实验说明项目效果", "将技术特征转化为清晰的用户价值", "尽早确认知识产权和材料署名"],
                "disclaimer": "这是本地演示报告；正式建议请配置真实模型，并以赛事官网最新通知为准。",
            }
        candidate_text = json.dumps(candidates, ensure_ascii=False)
        system = """你是大学生竞赛规划顾问。只能推荐候选列表中真实存在的比赛，不得虚构赛事、日期或资格。
综合项目方向、团队情况、报名时间和比赛要求，返回严格 JSON，不要 Markdown 代码块。JSON 结构：
{"summary":"总体判断","project_strengths":["..."],"project_gaps":["..."],
"matches":[{"contest_id":123,"match_score":88,"why_match":"...","eligibility":"...","deadline_note":"...","preparation":["..."]}],
"material_checklist":["..."],"timeline":[{"phase":"...","date_range":"...","tasks":["..."]}],
"improvement_suggestions":["..."],"disclaimer":"请以赛事官网为准"}
matches 最多 5 个，按匹配度降序。若资料不足，应明确写“需向主办方确认”，不得擅自断言资格。"""
        user = f"{project_context(project)}\n\n候选比赛（来自数据库）：\n{candidate_text}"
        result = await self.complete(
            [{"role": "system", "content": system}, {"role": "user", "content": user}],
            "recommendation",
            json_mode=True,
        )
        report = _json_from_text(result.text)
        allowed = {item["contest_id"] for item in candidates}
        matches = [item for item in report.get("matches", []) if item.get("contest_id") in allowed][:5]
        report["matches"] = matches
        report.setdefault("disclaimer", "AI 建议仅供参考，报名资格、赛程与材料要求请以赛事官网最新通知为准。")
        return report

    async def chat(self, project: Project, history: list[dict], message: str, competitions: list[dict]) -> str:
        if self.config.provider == "demo":
            self._record(uuid.uuid4().hex, "chat", None, 1, True, None)
            names = "、".join(item["contest_name"] for item in competitions[:3]) or "当前候选比赛"
            return f"这是演示回复。围绕“{message}”，建议先比较 {names} 的报名资格、提交物和剩余准备时间，再选择与项目现有成果最接近的一项。正式分析请在模型设置中配置你的模型。"
        system = f"""你是赛智荐的大学生竞赛顾问。回答必须基于用户项目和给出的真实比赛资料；涉及报名资格、截止时间时注明以官网为准。
{project_context(project)}
相关比赛资料：{json.dumps(competitions, ensure_ascii=False)}"""
        messages = [{"role": "system", "content": system}, *history[-16:], {"role": "user", "content": message}]
        result = await self.complete(messages, "chat")
        return result.text.strip()

    def _record(self, request_id: str, operation: str, usage: Any, latency_ms: int, success: bool, error: str | None) -> None:
        def value(name: str) -> int | None:
            if usage is None:
                return None
            if isinstance(usage, dict):
                return usage.get(name)
            return getattr(usage, name, None)

        self.db.add(
            UsageRecord(
                user_id=self.user_id,
                project_id=self.project_id,
                request_id=request_id,
                operation=operation,
                provider=self.config.provider,
                model_name=self.config.model_name,
                prompt_tokens=value("prompt_tokens"),
                completion_tokens=value("completion_tokens"),
                total_tokens=value("total_tokens"),
                latency_ms=latency_ms,
                success=success,
                error_type=error,
            )
        )
        self.db.commit()
