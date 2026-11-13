# Run the examples

These templates run on Kubernetes. Coder needs a provisioner that can reach the cluster. Steps 4 and 5 need Coder Premium for prebuilds. The templates also use the AI Gateway for Claude Code.

Do not push a template while it still names `registry.example.com`. That address is a placeholder, not a registry.

## Prepare the cluster

Pick a node that has room for the workspaces and prebuilds. Give it the label that the templates select:

```sh
kubectl label node NODE_NAME coder.com/pool=speed
```

Edit `cluster/workspace-rbac.yaml` if the Coder provisioner uses another ServiceAccount. The file assumes `coder` in the `coder` namespace. Then create the workspace namespace and its permissions:

```sh
kubectl apply -f cluster/workspace-rbac.yaml
```

The extra agent-sandbox template needs the agent-sandbox controller and a gVisor RuntimeClass. The five speed templates do not need that controller.

## Build the images

Set `CODER_BINARY_URL` to the Coder server that will run these workspaces. Build and push the full image for Step 3:

```sh
docker buildx build --platform linux/amd64 \
  --build-arg CODER_BINARY_URL=https://coder.example.com/bin/coder-linux-amd64 \
  -t registry.example.com/coder/workspace:speed-v1 \
  --push -f images/workspace/Dockerfile .
```

Build the same image without Claude Code for Steps 4 and 5:

```sh
docker buildx build --platform linux/amd64 \
  --build-arg CODER_BINARY_URL=https://coder.example.com/bin/coder-linux-amd64 \
  --build-arg INSTALL_CLAUDE_CODE=false \
  -t registry.example.com/coder/workspace:no-claude-v1 \
  --push -f images/workspace/Dockerfile .
```

If you want the extra Squid example, build its proxy image too:

```sh
docker buildx build --platform linux/amd64 \
  -t registry.example.com/coder/squid:7.6 \
  --push -f images/squid/Dockerfile .
```

Replace every example registry name in these commands. Use a fixed tag or image digest. Rebuild the image when you upgrade Coder.

The node can pull the images before a workspace starts. Replace the image names in `cluster/prepull.yaml` and `cluster/prepull-claim.yaml`. Then apply those two files. The baseline uses Ubuntu and has no pre-pull DaemonSet. Kubernetes can still cache Ubuntu after its first use.

## Push the templates

Sign in with the Coder CLI. Push Steps 1 and 2 first. Step 1 has no dependency lock file. Step 2 commits one.

```sh
coder templates push speed-1-baseline -d templates/01-baseline -O YOUR_ORG \
  --variable namespace=coder-workspaces
coder templates push speed-2-terraform -d templates/02-terraform -O YOUR_ORG \
  --variable namespace=coder-workspaces
```

Push Step 3 with the full image. Push Steps 4 and 5 with the image without Claude Code. Pass the image on every update because Coder keeps prior variable values.

```sh
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

The live demo kept the old Step 5 slug `speed-4-prebuilds`. This public example uses the clearer name `speed-5-optimized-prebuilds`. Both names refer to the same Terraform design.

## Extra agent-sandbox example

This example uses Squid to allow host names. Kubernetes NetworkPolicy blocks direct internet traffic from the workspace Pod. Squid allows only the selected names and ports.

Set `coder_egress_cidrs` to the IPv4 addresses of your Coder server. If its access URL uses a host name, set `coder_host_ip` to one of those addresses. Set `image` and `proxy_image` to the images that you pushed. The example file contains placeholder addresses.

Copy `examples/agent-sandbox-squid/variables.example.yaml` to `variables.local.yaml`. Change the values before you push the template. Keep `variables.local.yaml` out of Git.

```sh
coder templates push agent-sandbox-squid \
  -d examples/agent-sandbox-squid -O YOUR_ORG \
  --variables-file variables.local.yaml
```

If you do not need prebuilds, set `prebuild_instances: 0` in that file. Each running prebuild costs a Pod and a disk.
