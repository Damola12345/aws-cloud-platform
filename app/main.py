"""
Finzla assessment - minimal HTTP service.

Exposes:
  GET /health   -> liveness/readiness signal for the load balancer / ECS
  GET /version  -> app version, build number, git commit (from env vars)

Design notes:
  - No secrets or credentials are read from source; everything environment-
    specific comes from env vars injected at runtime (APP_ENV, APP_VERSION,
    BUILD_NUMBER, GIT_COMMIT).
  - Logs are structured JSON written to stdout/stderr only, so the container
    runtime (ECS/Fargate + awslogs driver) can ship them to CloudWatch
    without the app needing to know anything about the logging backend.
"""

import logging
import os
import sys
import time
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

# ---------------------------------------------------------------------------
# Structured logging to stdout (never to a file, never with secrets in it)
# ---------------------------------------------------------------------------


# Fields that may arrive via logger.info(msg, extra={...}) - deliberately
# explicit rather than dumping record.__dict__, so we never accidentally leak
# an internal logging attribute (or something a caller doesn't expect) into
# the emitted JSON.
STRUCTURED_FIELDS = ("http_method", "http_path", "http_status", "duration_ms", "error")


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        import json

        payload = {
            "timestamp": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "message": record.getMessage(),
            "service": "finzla-app",
            "env": os.getenv("APP_ENV", "unknown"),
        }
        for field in STRUCTURED_FIELDS:
            value = getattr(record, field, None)
            if value is not None:
                payload[field] = value
        return json.dumps(payload)


handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
logger = logging.getLogger("finzla-app")
logger.setLevel(logging.INFO)
logger.addHandler(handler)
logger.propagate = False

app = FastAPI(title="Finzla Assessment Service")

APP_ENV = os.getenv("APP_ENV", "development")
APP_VERSION = os.getenv("APP_VERSION", "0.0.0")
BUILD_NUMBER = os.getenv("BUILD_NUMBER", "local")
GIT_COMMIT = os.getenv("GIT_COMMIT", "unknown")


@app.middleware("http")
async def log_requests(request: Request, call_next):
    """
    Logs one structured line per request - including requests where the
    handler raises, not just successful ones. The exception is re-raised
    after logging so Starlette's own error handling still runs unchanged.
    """
    start = time.perf_counter()
    status_code = None
    error = None
    try:
        response = await call_next(request)
        status_code = response.status_code
        return response
    except Exception as exc:  # noqa: BLE001 - deliberately broad: log then re-raise everything
        error = repr(exc)
        raise
    finally:
        duration_ms = round((time.perf_counter() - start) * 1000, 2)
        logger.info(
            "http_request",
            extra={
                "http_method": request.method,
                "http_path": request.url.path,
                "http_status": status_code,
                "duration_ms": duration_ms,
                "error": error,
            },
        )


@app.get("/health")
async def health():
    """Used by the ALB target group health check and ECS container health check."""
    return JSONResponse(status_code=200, content={"status": "ok"})


@app.get("/version")
async def version():
    return JSONResponse(
        status_code=200,
        content={
            "version": APP_VERSION,
            "build": BUILD_NUMBER,
            "commit": GIT_COMMIT,
            "env": APP_ENV,
        },
    )


@app.get("/")
async def root():
    return {"service": "finzla-app", "env": APP_ENV}
