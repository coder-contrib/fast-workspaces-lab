# Cluster examples

You can read the templates and traces without running a cluster. Use these files only if you want to try the workspaces.

A Pod is a group of containers that Kubernetes runs together. A node is a VM that runs Pods. The examples expect a node with the label `coder.com/pool=speed`.

- `workspace-rbac.yaml` creates a workspace namespace and gives the Coder provisioner permission to create resources there.
- `prepull.yaml` pulls the full tool image onto the labeled node. Step 3 uses this image.
- `prepull-claim.yaml` pulls the image without Claude Code. Steps 4 and 5 use this image.
- `node-schedule.tf` is an optional EKS example that keeps one node ready at 9 AM on weekdays.

## Before you apply a file

A ServiceAccount is the identity that a program uses in Kubernetes. Make sure that your Coder provisioner uses the `coder` ServiceAccount in the `coder` namespace. If it uses another account, change the subject in `workspace-rbac.yaml` first.

Make sure that a node has the `coder.com/pool=speed` label. The templates and both image-pull examples select that label. If you do not use a labeled node, remove their node selectors and matching tolerations.

Build and push your images before you use the image-pull files. Replace `registry.example.com` in both files with your image names. The example address does not host an image.

Then apply the namespace file before the image-pull files:

```sh
kubectl apply -f cluster/workspace-rbac.yaml
kubectl apply -f cluster/prepull.yaml
kubectl apply -f cluster/prepull-claim.yaml
```

The five speed templates need Kubernetes access. The extra Squid template also needs the agent-sandbox controller and a gVisor RuntimeClass.

## Node schedule

You do not need `node-schedule.tf` to run the examples. It creates an AWS schedule only when you apply it with Terraform.

Do not enable the 5 PM scale-down while a workspace or prebuild uses the node. That action asks AWS to remove the node. Its default value is off.
