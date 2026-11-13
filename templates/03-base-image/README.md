# 3. Base image

This template uses an image that already has the agent, code-server, Claude Code, Chrome, Go, Node.js, AWS CLI, kubectl, and Playwright. Its startup script only prepares the home directory.

Build `images/workspace/Dockerfile` with Claude Code enabled. Pull the image onto warm nodes before you create workspaces. The measured workspace was ready in 16.5 seconds.
