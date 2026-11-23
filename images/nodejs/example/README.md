# Minimal Node.js container example

This folder contains a small Node.js app and a `Containerfile` to build a
container image on top of `nodejs:26-minimal`.

The minimal image ships the Node.js runtime only — no shell, no `npm`. The
`Containerfile` therefore installs dependencies in a builder stage, copies the
result into the runtime stage, and starts the app with `node` directly.

Build and run using podman or docker:

```bash
# Build
podman build -t nodejs-example -f Containerfile .

# Run
podman run -p 8080:8080 nodejs-example

# Test
curl -s http://localhost:8080/
```

The container listens on port 8080.
