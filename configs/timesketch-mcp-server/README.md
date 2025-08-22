# timesketch-mcp-server

## How to run

```
docker compose up -d
```

Launch a bash shell in the container:

```
docker compose exec timesketch-mcp /bin/bash
```

Launch the web server:

```
uv run python src/main.py --mcp-host 0.0.0.0 --mcp-port 8081
```
