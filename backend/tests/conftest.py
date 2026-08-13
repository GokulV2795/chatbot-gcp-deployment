import os

os.environ.setdefault("OPENROUTER_API_KEY", "test-key")

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)
