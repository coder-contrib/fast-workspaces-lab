# Agent-sandbox with a Squid firewall

This is an extra network example. It is not one of the five startup-speed steps.

The agent-sandbox controller creates the workspace Pod. Users pick an installed RuntimeClass in the Kernel isolation dropdown. gVisor is the fast default. You can offer Kata, Edera, or another isolation runtime. A second Pod runs Squid and accepts network requests by host name.

The workspace Pod can reach the Coder server and its own proxy. It has no direct internet route and no DNS. The proxy resolves names and blocks raw IP addresses and private addresses. Kubernetes NetworkPolicy enforces both Pod routes.

The template starts with Fully isolated. It keeps one prebuilt workspace for this default preset. Other presets allow GitHub, package registries, or public host names, but start fresh. Custom lets a user enter host names and choose ports 443 or 80. Set `prebuild_instances=0` if you do not have Coder Premium.

The workspace image uses the full tool set from `images/workspace/Dockerfile`. The Squid image uses `images/squid/Dockerfile`. Change the example image names before you push the template.

The template needs the agent-sandbox controller, its Sandbox resource, and a RuntimeClass installed on the speed nodes. Set `runtimes` to a comma-separated list of isolation classes those nodes support. Put the fastest one first. For example, use `gvisor,kata-qemu,kata-fc,edera` only if all four are installed. Do not list `runc` or another class that shares the node kernel. VM runtimes need nodes set up for virtualization. The Coder provisioner needs the namespace permissions in `cluster/workspace-rbac.yaml`.

If the Coder access URL uses a host name, set `coder_host_ip` to one of its public IPv4 addresses. Set `coder_egress_cidrs` to all addresses that it can use. Workspaces have no DNS and cannot discover an address change. Replace the documentation addresses in `variables.example.yaml`.

The template gives Claude Code a scoped AI Gateway token after a claim. It does not give the prebuild an owner's token. The workspace agent still receives its own Coder token from a Kubernetes Secret. Limit read access to this namespace.

The tests use mocked providers. Run `terraform init` and `terraform test` in this directory before you deploy changes.
