# Dockerfile for a development environment

FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    git \
    iputils-ping \
    curl

RUN pip install uv

ADD . /app
WORKDIR /app
RUN uv sync --all-groups

ENV PYTHONPATH /app

# Command to run the application
# We use 0.0.0.0 for the host to make it accessible from outside the container
# CMD ["uv", "run", "python", "main.py", "--mcp-host", "0.0.0.0", "--mcp-port", "8081"]

# Keep the container running
CMD ["sleep", "infinity"]

# Can be replaced with the following to run directly:
# CMD ["uv", "run", "python", "main.py", "--mcp-host", "0.0.0.0", "--mcp-port", "8081"]
