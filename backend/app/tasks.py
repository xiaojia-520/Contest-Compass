from __future__ import annotations

import asyncio
import sqlite3
import uuid
from dataclasses import asdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Callable

from celery import Task
from redis import Redis
from redis.exceptions import LockError

from saikr_crawler import SaikrCrawler, connect_db

from .celery_app import celery_app
from .config import ROOT_DIR, get_settings
from .database import SessionLocal
from .models import BackgroundJobRun
from .retrieval import get_retrieval_service


settings = get_settings()
RETRY_DELAYS = (15 * 60, 60 * 60, 180 * 60)
ACTIVE_STATUSES = ("queued", "running", "retrying")


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _ensure_run(run_id: int | None, job_type: str, trigger: str, task_id: str) -> int:
    with SessionLocal() as db:
        run = db.get(BackgroundJobRun, run_id) if run_id else None
        if run is None:
            run = BackgroundJobRun(job_type=job_type, trigger=trigger, status="queued", task_id=task_id)
            db.add(run)
        else:
            run.task_id = task_id
        db.commit()
        db.refresh(run)
        return run.id


def _update_run(run_id: int, **values) -> None:
    with SessionLocal() as db:
        run = db.get(BackgroundJobRun, run_id)
        if not run:
            return
        for key, value in values.items():
            setattr(run, key, value)
        db.commit()


def _backup_database() -> dict:
    source_path = Path(settings.competition_db_path)
    backup_dir = Path(settings.backup_dir)
    backup_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    target = backup_dir / f"saikr_competitions-{stamp}.db"
    temporary = target.with_suffix(".db.tmp")
    with sqlite3.connect(source_path) as source, sqlite3.connect(temporary) as destination:
        source.backup(destination)
        if destination.execute("PRAGMA quick_check").fetchone()[0] != "ok":
            raise RuntimeError("赛事数据库备份完整性检查失败")
    temporary.replace(target)

    backups = sorted(backup_dir.glob("saikr_competitions-*.db"), reverse=True)
    for old in backups[settings.backup_retention :]:
        old.unlink(missing_ok=True)
    return {"backup": str(target), "retained": min(len(backups), settings.backup_retention)}


def _run_crawler(*, full: bool) -> dict:
    connection = connect_db(Path(settings.competition_db_path), ROOT_DIR / "schema.sql")
    crawler = SaikrCrawler(
        connection,
        page_size=10,
        page_delay=settings.crawler_page_delay,
        detail_concurrency=settings.crawler_detail_concurrency,
        request_timeout=30,
        retries=3,
        sort=0 if full else 2,
    )
    try:
        summary = asyncio.run(
            crawler.run(
                start_page=1,
                max_pages=None if full else settings.crawler_incremental_max_pages,
                stop_after_unchanged_pages=None if full else settings.crawler_unchanged_page_limit,
            )
        )
        return asdict(summary)
    finally:
        connection.close()


def _incremental_handler() -> dict:
    crawl = _run_crawler(full=False)
    index = get_retrieval_service().sync_index(crawl.pop("changed_ids", []))
    return {"crawl": crawl, "index": index}


def _full_handler() -> dict:
    backup = _backup_database()
    crawl = _run_crawler(full=True)
    crawl.pop("changed_ids", None)
    index = get_retrieval_service().build_index()
    return {"backup": backup, "crawl": crawl, "index": index}


def _reindex_handler() -> dict:
    return {"index": get_retrieval_service().build_index()}


def _execute(task: Task, run_id: int | None, trigger: str, job_type: str, handler: Callable[[], dict]):
    task_id = str(task.request.id or uuid.uuid4().hex)
    run_id = _ensure_run(run_id, job_type, trigger, task_id)
    client = Redis.from_url(settings.redis_url)
    lock = client.lock("saizhijian:maintenance", timeout=6 * 60 * 60, blocking_timeout=0)
    acquired = lock.acquire(blocking=False)
    if not acquired:
        _update_run(
            run_id,
            status="skipped",
            finished_at=_now(),
            error_type="TaskAlreadyRunning",
            error_message="已有爬虫或索引任务正在运行",
        )
        return {"run_id": run_id, "status": "skipped"}

    _update_run(
        run_id,
        status="running",
        attempt=int(task.request.retries) + 1,
        started_at=_now(),
        error_type=None,
        error_message=None,
    )
    try:
        metrics = handler()
        _update_run(run_id, status="success", metrics=metrics, finished_at=_now())
        return {"run_id": run_id, "status": "success", "metrics": metrics}
    except Exception as exc:
        retry_index = int(task.request.retries)
        message = str(exc)[:4000]
        if retry_index < len(RETRY_DELAYS):
            _update_run(
                run_id,
                status="retrying",
                error_type=type(exc).__name__,
                error_message=message,
            )
            raise task.retry(exc=exc, countdown=RETRY_DELAYS[retry_index], max_retries=len(RETRY_DELAYS))
        _update_run(
            run_id,
            status="failed",
            error_type=type(exc).__name__,
            error_message=message,
            finished_at=_now(),
        )
        raise
    finally:
        try:
            lock.release()
        except LockError:
            pass


@celery_app.task(bind=True, name="app.tasks.incremental_crawl")
def incremental_crawl(self: Task, run_id: int | None = None, trigger: str = "scheduled"):
    return _execute(self, run_id, trigger, "incremental", _incremental_handler)


@celery_app.task(bind=True, name="app.tasks.full_crawl")
def full_crawl(self: Task, run_id: int | None = None, trigger: str = "scheduled"):
    return _execute(self, run_id, trigger, "full", _full_handler)


@celery_app.task(bind=True, name="app.tasks.rebuild_index")
def rebuild_index(self: Task, run_id: int | None = None, trigger: str = "manual"):
    return _execute(self, run_id, trigger, "reindex", _reindex_handler)


@celery_app.task(name="app.tasks.cleanup_history")
def cleanup_history() -> dict:
    cutoff = _now() - timedelta(days=settings.job_history_days)
    with SessionLocal() as db:
        rows = db.query(BackgroundJobRun).filter(BackgroundJobRun.created_at < cutoff).all()
        deleted = len(rows)
        for row in rows:
            db.delete(row)
        db.commit()
    return {"deleted": deleted, "cutoff": cutoff.isoformat()}
