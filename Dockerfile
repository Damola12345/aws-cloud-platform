# builder
FROM python:3.12-slim AS builder

WORKDIR /build
COPY app/requirements.txt .
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip "setuptools>=78.1.1" \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

# runtime
FROM python:3.12-slim AS runtime

RUN pip install --no-cache-dir --upgrade "setuptools>=78.1.1"

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN groupadd --system app && useradd --system --gid app --no-create-home app

COPY --from=builder /opt/venv /opt/venv
WORKDIR /app
COPY app/ ./app/

USER app
EXPOSE 8080

# Container health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=2)" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--no-access-log"]