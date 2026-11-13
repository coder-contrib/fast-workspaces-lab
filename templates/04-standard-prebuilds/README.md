# 4. Prebuild with a Pod replacement

Build `images/workspace/Dockerfile` with `INSTALL_CLAUDE_CODE=false`. A prebuild installs Claude Code into `/tmp/claude` inside its Pod.

The Deployment name uses the owner and workspace name. A claim changes both, so Terraform replaces the Pod. The new Pod loses `/tmp/claude` and the blocking startup script installs Claude again. The home disk keeps the clone.

Three claims were ready in 10.10 to 12.19 seconds. The median was 10.48 seconds. A special agent identity change keeps this Coder development build healthy after Pod replacement. It is not a general prebuild requirement.
