import os
import sys
from pathlib import Path

from cryptography.fernet import Fernet


TEST_DB = Path(__file__).with_name("test.db")
if TEST_DB.exists():
    TEST_DB.unlink()
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ["DATABASE_URL"] = f"sqlite:///{TEST_DB.as_posix()}"
os.environ["JWT_SECRET"] = "test-secret-at-least-sixteen-characters"
os.environ["ENCRYPTION_KEY"] = Fernet.generate_key().decode()

from fastapi.testclient import TestClient  # noqa: E402
from app.main import app  # noqa: E402
from app.database import SessionLocal  # noqa: E402
from app.models import User  # noqa: E402
from app import admin_api  # noqa: E402


def test_schedule_helpers_return_future_times():
    next_daily = admin_api._next_daily(admin_api.time(2), admin_api.time(14))
    next_weekly = admin_api._next_weekly(6, admin_api.time(3))
    assert next_daily > admin_api.datetime.now(admin_api.SHANGHAI)
    assert next_weekly > admin_api.datetime.now(admin_api.SHANGHAI)


def test_auth_project_and_model_config():
    with TestClient(app) as client:
        registered = client.post(
            "/api/auth/register",
            json={"username": "tester", "email": "tester@example.com", "password": "strong-pass-123"},
        )
        assert registered.status_code == 201, registered.text
        token = registered.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        project = client.post(
            "/api/projects",
            headers=headers,
            json={"title": "校园节能监测系统", "description": "通过传感器和算法降低教学楼能耗"},
        )
        assert project.status_code == 201, project.text
        assert client.get("/api/projects", headers=headers).json()[0]["title"] == "校园节能监测系统"

        saved = client.put(
            "/api/model-config",
            headers=headers,
            json={"provider": "deepseek", "model_name": "deepseek/deepseek-chat", "api_key": "sk-test"},
        )
        assert saved.status_code == 200, saved.text
        assert saved.json()["has_api_key"] is True
        assert "sk-test" not in saved.text


def test_admin_permission_and_manual_enqueue(monkeypatch):
    with TestClient(app) as client:
        normal = client.post(
            "/api/auth/register",
            json={"username": "normal-user", "password": "strong-pass-123"},
        ).json()
        normal_headers = {"Authorization": f"Bearer {normal['access_token']}"}
        assert client.get("/api/admin/jobs", headers=normal_headers).status_code == 403

        admin = client.post(
            "/api/auth/register",
            json={"username": "admin-user", "password": "strong-pass-123"},
        ).json()
        with SessionLocal() as db:
            user = db.get(User, admin["user"]["id"])
            user.is_admin = True
            db.commit()
        admin_headers = {"Authorization": f"Bearer {admin['access_token']}"}
        assert client.get("/api/auth/me", headers=admin_headers).json()["is_admin"] is True

        class Result:
            id = "test-celery-task-id"

        monkeypatch.setattr(
            admin_api.TASKS["incremental"],
            "apply_async",
            lambda args: Result(),
        )
        response = client.post("/api/admin/jobs/incremental", headers=admin_headers)
        assert response.status_code == 202, response.text
        assert response.json()["job"]["task_id"] == "test-celery-task-id"
