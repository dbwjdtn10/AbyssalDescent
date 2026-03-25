"""Tests for the /api/health endpoint."""

from fastapi.testclient import TestClient


class TestHealthEndpoint:
    """Verify the server health check endpoint."""

    def test_health_returns_200(self, client: TestClient) -> None:
        """GET /api/health should return HTTP 200."""
        response = client.get("/api/health")
        assert response.status_code == 200

    def test_health_body_has_required_fields(self, client: TestClient) -> None:
        """Response must contain status, version, and service keys."""
        data = client.get("/api/health").json()
        assert "status" in data
        assert "version" in data
        assert "service" in data

    def test_health_status_is_ok(self, client: TestClient) -> None:
        """The status field should be 'ok'."""
        data = client.get("/api/health").json()
        assert data["status"] == "ok"

    def test_health_version_is_string(self, client: TestClient) -> None:
        """The version field should be a non-empty string."""
        data = client.get("/api/health").json()
        assert isinstance(data["version"], str)
        assert len(data["version"]) > 0

    def test_health_service_is_string(self, client: TestClient) -> None:
        """The service field should be a non-empty string."""
        data = client.get("/api/health").json()
        assert isinstance(data["service"], str)
        assert len(data["service"]) > 0
