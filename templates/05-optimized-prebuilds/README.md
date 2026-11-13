# 5. Prebuild that keeps its Pod

This template uses the same image and `claude-startup.sh` as Step 4. A prebuild installs Claude Code into `/tmp/claude` inside its Pod.

The Deployment name uses the workspace ID, which does not change on claim. The claim keeps the Pod and its Claude install. The blocking startup script finds the executable and skips the install.

Three claims were ready in 1.68 to 5.79 seconds. The median was 1.77 seconds. If the workspace stops, its Pod goes away and the next start installs Claude again.
