# How we measured startup

Coder records a build timeline for Terraform, the agent connection, and startup scripts. The ready time spans the first recorded action to the last one. Actions can overlap. Adding their durations gives the wrong total.

These runs used a warm EKS node. Kubernetes had the Ubuntu image and the tool images on that node. A new node and a cold image pull add time that this table does not measure.

| Step | Ready time | Terraform | Agent connection | Startup script |
| --- | ---: | ---: | ---: | ---: |
| 1. Baseline | 98.1 s | 8.8 s | 8.8 s | 80.0 s |
| 2. Terraform | 98.7 s | 1.7 s | 20.4 s | 76.1 s |
| 3. Base image | 16.5 s | 3.8 s | 11.1 s | 0.004 s |
| 4. Standard prebuild | 10.5 s median | 1.6 s median | 0.3 s median | 7.9 s median |
| 5. Optimized prebuild | 1.8 s median | 1.3 s median | 0.3 s median | 0.006 s median |

The first three rows are one earlier run each. Step 3 used an earlier full tool image. The last two rows are medians from three later claims per template. Steps 4 and 5 used the same image without Claude Code. Both had installed Claude into `/tmp/claude` during the prebuild.

Step 4 claim times were 12.19, 10.48, and 10.10 seconds. The claim replaced the Pod and reinstalled Claude each time. Its install scripts took 9.67, 7.89, and 7.51 seconds. The persistent disk stayed.

Step 5 claim times were 1.77, 5.79, and 1.68 seconds. The claim kept the Pod and skipped the install. One claim spent 4.06 seconds in Terraform. The median Step 4 to Step 5 saving was 8.72 seconds. Three runs do not prove a guaranteed saving.

Step 3 used an image that already included Claude. Steps 4 and 5 did not. The Step 3 to Step 4 difference combines an image change with a prebuild. Only Steps 4 and 5 isolate the Pod behavior.

## Provider cache

Step 1 has no provider version pins and no lock file in its source. Coder still creates a lock file during template import. This deployment captures it and skips `terraform init` on warm workspace builds.

Step 2 reduced the Terraform stage by about 7 seconds because the build stopped waiting for a Kubernetes Deployment rollout. The workspace did not become ready sooner. In a separate Terraform test, an unpinned warm-cache init took about 2.2 seconds. A pinned init with a lock file took about 0.9 seconds. Those are not Coder workspace-build savings.

## Small spot tests

A 61 MB Coder binary download took 0.17 to 0.34 seconds on the warm node. One fresh Claude Code install took 11.2 seconds. These tests ran separately from the five workspace runs. They do not break the 80-second Baseline script into exact parts.

The first claim of the Pod-replacing template reused the old agent identity. On this development build, Coder marked that agent as shutting down. The measured version replaces the agent identity when the owner changes. It passed three new claims. That workaround is not a general prebuild requirement.

`data/speeds.csv` lists the five values. `traces/` holds redacted API timings for the three fresh creates and six claims. The redaction changes identifiers but keeps every time and script status.
