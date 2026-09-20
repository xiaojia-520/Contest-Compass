from __future__ import annotations

from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException, Query, status
from redis import Redis
from sqlalchemy import select
from sqlalchemy.orm import Session

from .celery_app import celery_app
from .competition import CompetitionRepository
from .config import get_settings
from .database import get_db
from .models import BackgroundJobRun, User
from .retrieval import get_retrieval_service
from .schemas import AdminOverviewOut, BackgroundJobOut, TaskTriggerOut
from .security import require_admin
from .tasks import ACTIVE_STATUSES, full_crawl, incremental_crawl, rebuild_index


router = APIRouter(prefix="/api/admin", tags=["admin"])
settings = get_settings()
TASKS = {
    "incremental": incremental_crawl,
    "full": full_crawl,
    "reindex": rebuild_index,
}
SHANGHAI = ZoneInfo("Asia/Shanghai")


def _next_daily(*times: time) -> datetime:
    now = datetime.now(SHANGHAI)
    candidates = [datetime.combine(now.date(), item, SHANGHAI) for item in times]
    candidates.extend([item + timedelta(days=1) for item in candidates])
    return min(item for item in candidates if item > now)


def _next_weekly(weekday: int, at: time) -> datetime:
    now = datetime.now(SHANGHAI)
    candidate = datetime.combine(
        now.date() + timedelta(days=(weekday - now.weekday()) % 7), at, SHANGHAI
    )
    return candidate if candidate > now else candidate + timedelta(days=7)


def _schedule_text(label: str, next_run: datetime) -> str:
    return f"{label}；下次 {next_run:%Y-%m-%d %H:%M}（北京时间）"


@router.get("/overview", response_model=AdminOverviewOut)
def overview(_: User = Depends(require_admin), db: Session = Depends(get_db)):
    try:
        redis_ok = bool(Redis.from_url(settings.redis_url).ping())
    except Exception:
        redis_ok = False
    try:
        replies = celery_app.control.inspect(timeout=0.7).ping() or {}
        worker_ok = bool(replies)
    except Exception:
        worker_ok = False
    try:
        vector_count = get_retrieval_service().vector_count()
    except Exception:
        vector_count = None
    counts = CompetitionRepository().counts()
    active = db.scalar(
        select(BackgroundJobRun)
        .where(BackgroundJobRun.status.in_(ACTIVE_STATUSES))
        .order_by(BackgroundJobRun.created_at.desc())
    )
    recent = list(
        db.scalars(select(BackgroundJobRun).order_by(BackgroundJobRun.created_at.desc()).limit(20))
    )
    return AdminOverviewOut(
        redis_ok=redis_ok,
        worker_ok=worker_ok,
        active_job=active,
        recent_jobs=recent,
        competition_total=counts["total"],
        competition_active=counts["active"],
        competition_eligible=counts["eligible"],
        vector_count=vector_count,
        schedules={
            "incremental": _schedule_text(
                "每天 02:00、14:00", _next_daily(time(2), time(14))
            ),
            "full": _schedule_text("每周日 03:00", _next_weekly(6, time(3))),
            "cleanup": _schedule_text("每天 04:30", _next_daily(time(4, 30))),
        },
    )


@router.get("/jobs", response_model=list[BackgroundJobOut])
def jobs(
    limit: int = Query(default=50, ge=1, le=200),
    _: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    return list(db.scalars(select(BackgroundJobRun).order_by(BackgroundJobRun.created_at.desc()).limit(limit)))


@router.post("/jobs/{job_type}", response_model=TaskTriggerOut, status_code=status.HTTP_202_ACCEPTED)
def trigger_job(
    job_type: str,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    task = TASKS.get(job_type)
    if not task:
        raise HTTPException(status_code=404, detail="未知任务类型")
    active = db.scalar(select(BackgroundJobRun.id).where(BackgroundJobRun.status.in_(ACTIVE_STATUSES)))
    if active:
        raise HTTPException(status_code=409, detail="已有爬虫或索引任务正在排队或运行")
    job = BackgroundJobRun(job_type=job_type, trigger="manual", status="queued", requested_by=user.id)
    db.add(job)
    db.commit()
    db.refresh(job)
    try:
        result = task.apply_async(args=[job.id, "manual"])
        job.task_id = result.id
        db.commit()
        db.refresh(job)
    except Exception as exc:
        job.status = "failed"
        job.error_type = type(exc).__name__
        job.error_message = str(exc)[:4000]
        db.commit()
        raise HTTPException(status_code=503, detail="任务队列不可用")
    return TaskTriggerOut(job=job)
