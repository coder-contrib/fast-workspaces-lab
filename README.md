# Workspace startup lab

This repository supports Ben Potter's Coder Labs talk. It compares five ways to start a Coder workspace on Kubernetes.

A prebuild is a workspace that Coder starts before someone claims it. A trace is a saved record of a workspace build timeline.

| Step | What changes | Ready time |
| --- | --- | ---: |
| 1. Baseline | Install tools each time a workspace starts. | 98.1 s |
| 2. Terraform | Pin dependencies and stop waiting for the Pod rollout. | 98.7 s |
| 3. Base image | Put the tools in an image before a workspace starts. | 16.5 s |
| 4. Standard prebuild | Replace the Pod and reinstall Claude Code at claim. | 10.5 s median |
| 5. Optimized prebuild | Keep the Pod and skip that install. | 1.8 s median |

The first three times came from one earlier run each. Steps 4 and 5 show medians from three later claims each. The node and images were warm. Read [the measurement notes](docs/measurements.md) before you use the numbers.

The Step 2 workspace did not become ready sooner. Its Terraform job ended sooner because the template stopped waiting for a Pod rollout. On this Coder build, the provisioner already reuses cached providers.

Steps 4 and 5 use the same image without Claude Code. Both prebuilds install Claude into the Pod filesystem. Step 4 replaces that Pod and installs Claude again. Step 5 keeps the Pod and skips the install. Its median was 8.7 seconds faster. Step 3 uses a full image with Claude already included, so Step 3 and Step 4 differ in more than one way. The [prebuild guide](docs/prebuilds.md) shows the two claim templates side by side.

## Files

- [`templates/`](templates/): The five Terraform templates. Step 1 has no dependency lock file.
- [`images/`](images/): The workspace image and the Squid proxy image. Squid allows network access by host name.
- [`cluster/`](cluster/): A namespace, permissions, and an example that pulls the image onto warm nodes.
- [`examples/agent-sandbox-squid/`](examples/agent-sandbox-squid/): A separate agent-sandbox example with host-name rules.
- [`traces/`](traces/): Redacted Coder build timelines. The timing values are unchanged.
- [`slides/`](slides/): The final PDF will go here when the presenter provides it.

## Use the examples

Read [the setup guide](docs/run.md) before you push a template. The image names are placeholders. Replace them with images in your registry.

The templates need Coder Premium for prebuilds and the AI Gateway. The agent-sandbox example also needs its controller and a runtime such as gVisor.

Some template code adapts examples from `coder/registry`. See `LICENSE`. This repository was prepared with Coder Agents for Ben Potter.
