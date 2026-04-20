# Yeti MCP Server
# Built from upstream: https://github.com/yeti-platform/yeti-mcp

FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN pip install uv

# Clone the upstream Yeti MCP server
RUN git clone --depth 1 https://github.com/yeti-platform/yeti-mcp.git .

RUN uv sync --all-groups

ENV PYTHONPATH=/app

# Default command — start the MCP server on port 8082
CMD ["uv", "run", "python", "-m", "src.server", "--mcp-host", "0.0.0.0", "--mcp-port", "8082"]
