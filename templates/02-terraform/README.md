# 2. Terraform

This template keeps the same startup installs as Step 1. It pins provider and module versions and includes `.terraform.lock.hcl`.

The build stops waiting for a Kubernetes Deployment rollout. That shortened the Terraform job, but the measured workspace took 98.7 seconds to become ready. The dependency lock did not produce a measured seven-second ready-time saving on this Coder build.
