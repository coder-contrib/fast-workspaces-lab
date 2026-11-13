# Try the templates

You need a Coder deployment, a Kubernetes cluster, Docker, and a registry for the images. If you only want the talk data, start with `docs/measurements.md` instead.

Before you push a template, prepare the namespace and a labeled node. Follow [`cluster/README.md`](../cluster/README.md). The image names below are examples. Replace `registry.example.com` with your registry.

## Build the images

Set `CODER_BINARY_URL` to the Coder server that will run the workspaces. Build the full image for Step 3:

```sh
docker buildx build --platform linux/amd64 \
  --build-arg CODER_BINARY_URL=https://coder.example.com/bin/coder-linux-amd64 \
  -t registry.example.com/coder/workspace:speed-v1 \
  --push -f images/workspace/Dockerfile .
```

Steps 4 and 5 use the same image without Claude Code. They install Claude inside a running prebuild instead:

```sh
docker buildx build --platform linux/amd64 \
  --build-arg CODER_BINARY_URL=https://coder.example.com/bin/coder-linux-amd64 \
  --build-arg INSTALL_CLAUDE_CODE=false \
  -t registry.example.com/coder/workspace:no-claude-v1 \
  --push -f images/workspace/Dockerfile .
```

If you want the extra Squid template, build its proxy image too:

```sh
docker buildx build --platform linux/amd64 \
  -t registry.example.com/coder/squid:7.6 \
  --push -f images/squid/Dockerfile .
```

## Push the five templates

Sign in with the Coder CLI. Replace `YOUR_ORG` and the image names. Do not push a template that still names `registry.example.com`.

```sh
coder templates push speed-1-baseline -d templates/01-baseline -O YOUR_ORG \
  --variable namespace=coder-workspaces
coder templates push speed-2-terraform -d templates/02-terraform -O YOUR_ORG \
  --variable namespace=coder-workspaces
coder templates push speed-3-base-image -d templates/03-base-image -O YOUR_ORG \
  --variable namespace=coder-workspaces \
  --variable image=registry.example.com/coder/workspace:speed-v1
coder templates push speed-4-standard-prebuilds -d templates/04-standard-prebuilds -O YOUR_ORG \
  --variable namespace=coder-workspaces \
  --variable image=registry.example.com/coder/workspace:no-claude-v1 \
  --variable prebuild_instances=2
coder templates push speed-5-optimized-prebuilds -d templates/05-optimized-prebuilds -O YOUR_ORG \
  --variable namespace=coder-workspaces \
  --variable image=registry.example.com/coder/workspace:no-claude-v1 \
  --variable prebuild_instances=2
```

Coder Premium is needed for prebuilds and the AI Gateway. Each running prebuild uses a Pod and a disk. Use `prebuild_instances=0` if you do not want a pool.

The [extra agent-sandbox guide](../examples/agent-sandbox-squid/README.md) explains its separate image and network values.
