# Small official Python image
FROM python:3.12-slim

# Print logs immediately (no buffering) and don't write .pyc files
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# Install dependencies first, so Docker can reuse this layer when only code changes
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY publisher.py .

# Never run as root inside the container
RUN useradd --create-home appuser
USER appuser

CMD ["python", "publisher.py"]