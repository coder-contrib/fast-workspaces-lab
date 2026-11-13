# Start a Coder workspace faster

This is the small demo for Ben Potter's Coder Labs talk. It shows five workspace templates and the time each took to become ready.

A template tells Coder how to make a workspace. A prebuild is a workspace that Coder starts before someone claims it. An image holds the tools that a workspace uses. A trace is a saved build timeline.

| Step | What the workspace does | Ready time |
| --- | --- | ---: |
| 1. Baseline | Installs tools after the Pod starts. | 98.1 s |
| 2. Terraform | Uses pinned dependencies and a shorter build job. | 98.7 s |
| 3. Base image | Starts with tools already in the image. | 16.5 s |
| 4. Standard prebuild | Replaces the Pod and installs Claude Code again. | 10.5 s median |
| 5. Optimized prebuild | Keeps the Pod and skips that install. | 1.8 s median |

These are demo measurements on one warm node. Step 2 did not make the workspace ready sooner. Steps 4 and 5 use the same image without Claude Code. Read [how the timings work](docs/measurements.md) before you use the numbers.

## Start here

- Read [the prebuild guide](docs/prebuilds.md) to see why one claim replaces its Pod.
- Read [the run guide](docs/run.md) to build images and push templates.
- Open [`traces/`](traces/) to see the timing data behind the table.

The five templates are in [`templates/`](templates/). The image recipes are in [`images/`](images/). The optional cluster examples have [their own guide](cluster/README.md).

The extra [agent-sandbox and Squid template](examples/agent-sandbox-squid/) shows network rules by host name. It is not a sixth speed step.

Ben will add the final PDF to [`slides/`](slides/) when it is ready. Some template code adapts examples from `coder/registry`. See `LICENSE`. Coder Agents prepared this repository for Ben Potter.
