from app.core.config import get_settings


def test_chat_rejects_missing_secret(client, monkeypatch):
    monkeypatch.setenv("APP_SHARED_SECRET", "expected-secret")
    get_settings.cache_clear()

    response = client.post("/chat", json={"messages": [{"role": "user", "content": "hi"}]})

    assert response.status_code == 401
    get_settings.cache_clear()
