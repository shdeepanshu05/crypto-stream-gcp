FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# Dependencies first: this layer is cached until requirements.txt changes.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY *.py ./

# Never run as root.
RUN useradd --create-home appuser
USER appuser

# Each Cloud Run job passes its own argument: "coingecko" or "fx".
ENTRYPOINT ["python", "main.py"]