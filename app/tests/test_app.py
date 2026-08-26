import os

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("APP_VERSION", "1.2.3")
os.environ.setdefault("BUILD_NUMBER", "42")
os.environ.setdefault("GIT_COMMIT", "abc1234")

from fastapi.testclient import TestClient  # noqa: E402
from fastapi import FastAPI  # noqa: E402
from app.main import app, log_requests  # noqa: E402

client = TestClient(app)


def test_health_returns_200_ok():
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_version_returns_expected_fields():
    resp = client.get("/version")
    assert resp.status_code == 200
    body = resp.json()
    assert body["version"] == "1.2.3"
    assert body["build"] == "42"
    assert body["commit"] == "abc1234"
    assert body["env"] == "test"


def test_root_reports_env():
    resp = client.get("/")
    assert resp.status_code == 200
    assert resp.json()["service"] == "finzla-app"


def test_logging_middleware_still_runs_when_handler_raises():
    """
    Regression test for the logging middleware: a request that raises inside
    the handler must still produce a log line (with the error captured) and
    must still propagate as a 500, rather than the exception being swallowed
    or the request going unlogged.

    Exercises this against a throwaway FastAPI app that reuses the real
    log_requests middleware, rather than adding a permanent /boom route to
    the actual application's route table.

    Attaches a handler directly to app.main's logger for the duration of the
    test, rather than relying on pytest's caplog (which only sees records
    that propagate to the root logger - our logger deliberately sets
    propagate=False, see main.py) or on capturing stdout (our StreamHandler
    holds a reference to the real fd captured at import time, before
    pytest's per-test capture fixtures attach).
    """
    import logging

    class ListHandler(logging.Handler):
        def __init__(self):
            super().__init__()
            self.records = []

        def emit(self, record):
            self.records.append(record)

    from app.main import logger as app_logger

    test_app = FastAPI()
    test_app.middleware("http")(log_requests)

    @test_app.get("/boom")
    async def boom():
        raise ValueError("deliberate failure")

    list_handler = ListHandler()
    app_logger.addHandler(list_handler)

    try:
        boom_client = TestClient(test_app, raise_server_exceptions=False)
        resp = boom_client.get("/boom")
    finally:
        app_logger.removeHandler(list_handler)

    assert resp.status_code == 500

    boom_records = [r for r in list_handler.records if getattr(r, "http_path", None) == "/boom"]
    assert boom_records, "expected a log record for the /boom request even though it raised"
    assert "deliberate failure" in boom_records[0].error
