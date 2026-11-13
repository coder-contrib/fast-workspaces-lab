# 1. Baseline

This template starts from plain Ubuntu. Its Pod installs the agent and basic tools. Its blocking startup script installs Chrome, Go, Node.js, Claude Code, and other tools.

The source has no provider version pins or `.terraform.lock.hcl`. Current Coder builds can still create and reuse a lock file during template import. The measured workspace was ready in 98.1 seconds on a warm node.
