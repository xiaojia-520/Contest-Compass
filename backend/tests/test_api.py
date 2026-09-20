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
