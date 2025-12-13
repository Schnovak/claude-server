FROM python:3.12-slim

# Install system dependencies including firejail for sandboxing
RUN apt-get update && apt-get install -y \
    firejail \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js and Claude CLI
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g @anthropic-ai/claude-code \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy requirements first for caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY . .

# Create directories
RUN mkdir -p /app/data /app/users /app/data/logs

# Environment
ENV PYTHONUNBUFFERED=1
ENV REQUIRE_SANDBOX=true

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
