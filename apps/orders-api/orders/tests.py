import pytest


def test_health_ok_even_with_unknown_host(client):
    # ALB health checks send the task IP as Host; must not 400.
    response = client.get("/health", HTTP_HOST="10.0.1.23")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


@pytest.mark.django_db
def test_orders_lists_seeded_rows(client):
    response = client.get("/orders")
    assert response.status_code == 200
    body = response.json()
    assert body["count"] == 3
    assert {"id", "customer", "item", "quantity", "status", "created_at"} <= body["orders"][0].keys()


@pytest.mark.django_db
def test_every_response_carries_app_version(client, settings):
    settings.APP_VERSION = "abc1234"
    assert client.get("/orders")["X-App-Version"] == "abc1234"
    assert client.get("/health")["X-App-Version"] == "abc1234"


@pytest.mark.django_db
def test_orders_rejects_post(client):
    assert client.post("/orders").status_code == 405


def test_unknown_host_rejected_on_app_routes(client):
    assert client.get("/orders", HTTP_HOST="evil.example.com").status_code == 400
