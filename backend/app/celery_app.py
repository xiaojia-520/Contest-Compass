from celery import Celery
from celery.schedules import crontab

from .config import get_settings


settings = get_settings()
celery_app = Celery(
    "saizhijian",
    broker=settings.celery_broker_url,
    backend=settings.celery_result_backend,
    include=["app.tasks"],
)
celery_app.conf.update(
    timezone="Asia/Shanghai",
    enable_utc=True,
    task_track_started=True,
    task_time_limit=6 * 60 * 60,
    task_soft_time_limit=5 * 60 * 60 + 50 * 60,
    worker_prefetch_multiplier=1,
    task_acks_late=True,
    broker_connection_retry_on_startup=True,
    beat_schedule={
        "incremental-crawl-twice-daily": {
            "task": "app.tasks.incremental_crawl",
            "schedule": crontab(hour="2,14", minute=0),
        },
        "full-crawl-weekly": {
            "task": "app.tasks.full_crawl",
            "schedule": crontab(hour=3, minute=0, day_of_week="sunday"),
        },
        "cleanup-job-history": {
            "task": "app.tasks.cleanup_history",
            "schedule": crontab(hour=4, minute=30),
        },
    },
)
