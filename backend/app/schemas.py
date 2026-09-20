from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator


class UserCreate(BaseModel):
    username: str = Field(min_length=3, max_length=64, pattern=r"^[\w\-\u4e00-\u9fff]+$")
    email: str | None = Field(default=None, max_length=255)
    password: str = Field(min_length=8, max_length=128)


class LoginRequest(BaseModel):
    account: str
    password: str


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    username: str
    email: str | None
    is_admin: bool = False
    created_at: datetime


class UserPreferencesIn(BaseModel):
    reminders_enabled: bool


class UserPreferencesOut(BaseModel):
    reminders_enabled: bool


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


class ModelConfigIn(BaseModel):
    provider: str = Field(min_length=2, max_length=50)
    model_name: str = Field(min_length=2, max_length=200)
    api_base: str | None = Field(default=None, max_length=500)
    api_key: str | None = Field(default=None, max_length=1000)

    @field_validator("api_base")
    @classmethod
    def validate_base(cls, value: str | None) -> str | None:
        if value and not value.startswith(("http://", "https://")):
            raise ValueError("API 地址必须以 http:// 或 https:// 开头")
        return value.rstrip("/") if value else None


class ModelConfigOut(BaseModel):
    provider: str
    model_name: str
    api_base: str | None
    has_api_key: bool
    updated_at: datetime | None = None


class ProjectBase(BaseModel):
    title: str = Field(min_length=1, max_length=160)
    description: str = Field(default="", max_length=10000)
    markdown_content: str = Field(default="", max_length=200000)
    school: str = Field(default="", max_length=160)
    education_level: str = Field(default="", max_length=80)
    grade: str = Field(default="", max_length=80)
    major: str = Field(default="", max_length=160)
    region: str = Field(default="", max_length=120)
    team_size: int = Field(default=1, ge=1, le=100)
    weekly_hours: int = Field(default=5, ge=1, le=168)
    reminders_enabled: bool = True


class ProjectCreate(ProjectBase):
    pass


class ProjectUpdate(ProjectBase):
    pass


class ProjectOut(ProjectBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    owner_id: int
    created_at: datetime
    updated_at: datetime


class CompetitionOut(BaseModel):
    contest_id: int
    contest_name: str
    level_name: str | None = None
    status_name: str | None = None
    category: str | None = None
    register_end_at: int | None = None
    contest_start_at: int | None = None
    contest_end_at: int | None = None
    source_url: str
    content_excerpt: str = ""


class RecommendationOut(BaseModel):
    id: int
    project_id: int
    status: str
    report: dict[str, Any]
    candidates: list[CompetitionOut]
    created_at: datetime


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=10000)


class ChatMessageOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    role: str
    content: str
    sources: list[Any]
    created_at: datetime


class ChatResponse(BaseModel):
    user_message: ChatMessageOut
    assistant_message: ChatMessageOut


class UsageOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    operation: str
    provider: str
    model_name: str
    prompt_tokens: int | None
    completion_tokens: int | None
    total_tokens: int | None
    latency_ms: int | None
    success: bool
    created_at: datetime


class BackgroundJobOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    task_id: str | None
    job_type: str
    trigger: str
    status: str
    attempt: int
    metrics: dict[str, Any]
    error_type: str | None
    error_message: str | None
    requested_by: int | None
    created_at: datetime
    started_at: datetime | None
    finished_at: datetime | None


class AdminOverviewOut(BaseModel):
    redis_ok: bool
    worker_ok: bool
    active_job: BackgroundJobOut | None
    recent_jobs: list[BackgroundJobOut]
    competition_total: int
    competition_active: int
    competition_eligible: int
    vector_count: int | None
    schedules: dict[str, str]


class TaskTriggerOut(BaseModel):
    job: BackgroundJobOut


class ReminderOut(BaseModel):
    project_id: int
    project_title: str
    contest_id: int
    contest_name: str
    register_end_at: int


class AppReleaseIn(BaseModel):
    platform: str = Field(pattern=r"^(android|ios|windows|macos|web)$")
    version: str = Field(min_length=1, max_length=40, pattern=r"^\d+\.\d+\.\d+$")
    build_number: int = Field(default=1, ge=1)
    minimum_supported_version: str | None = Field(
        default=None, max_length=40, pattern=r"^\d+\.\d+\.\d+$"
    )
    release_notes: str = Field(default="", max_length=20000)
    download_url: str = Field(max_length=1000, pattern=r"^https://")
    sha256: str | None = Field(
        default=None, min_length=64, max_length=64, pattern=r"^[0-9a-fA-F]{64}$"
    )
    mandatory: bool = False
    published: bool = False


class AppReleaseOut(AppReleaseIn):
    model_config = ConfigDict(from_attributes=True)
    id: int
    created_at: datetime
    published_at: datetime | None


class LatestReleaseOut(BaseModel):
    platform: str
    version: str
    build_number: int
    minimum_supported_version: str | None
    release_notes: str
    download_url: str
    sha256: str | None
    mandatory: bool
