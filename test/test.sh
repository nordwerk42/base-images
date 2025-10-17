set -ex



platform=${1:-"amd64"}
# Create a named volume for Nix store persistence (only needs to be done once)
docker volume create nix-store-cache 2>/dev/null || true

# Run the nix container matching the platform architecture
docker run -it --platform="linux/${platform}" \
  -v nix-store-cache:/nix \
  -v $PWD/nix.conf:/etc/nix/nix.conf \
  -v $PWD/..:/app \
  -v ~/.ssh:/root/.ssh \
  nixos/nix bash -c "cd /app && nix build --impure -L '.#\"nodejs-24-${platform}\"' && cp \$(readlink result) ./nodejs-24-${platform}"

# 2. load the image into docker
docker load < ../nodejs-24-${platform}

# 3. build the example container
docker build -f Containerfile --platform="linux/${platform}" -t node-example:latest ../example

docker run --platform="linux/${platform}" --rm -it -p 8080:8080 node-example:latest