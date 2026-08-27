# builder
FROM python:3.12-slim AS builder

WORKDIR /build
COPY app/requirements.txt .
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip "setuptools>=78.1.1" \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

# runtime
FROM python:3.12-slim AS runtime

RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*
RUN apt-get purge -y python3-setuptools python3-setuptools-whl 2>&1 | tee /tmp/purge.log; \
    (grep -q "Removing python3-setuptools" /tmp/purge.log && echo "apt purge: removed the apt-level package") \
    || echo "apt purge: nothing removed (package absent or already gone) - relying on the exact-version fallback below"; \
    rm -f /tmp/purge.log

RUN find / -xdev \( -iname "setuptools-70.3.0.egg-info" -o -iname "setuptools-70.3.0.dist-info" \) 2>/dev/null | xargs -r rm -rf

RUN pip install --no-cache-dir --upgrade pip "setuptools>=78.1.1"


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
