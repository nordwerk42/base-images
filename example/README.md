# Minimal Flask container example

This folder contains a minimal Flask app and a `Containerfile` to build a container image.

Build and run using podman or docker:

```bash
# Build
podman build -t flask-example -f Containerfile .

# Run
podman run -p 8080:8080 flask-example

# Test
curl -s http://localhost:8080/
```

The container listens on port 8080.
