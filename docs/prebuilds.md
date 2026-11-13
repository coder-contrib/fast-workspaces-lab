# Two ways to claim a prebuild

Steps 4 and 5 use the same image without Claude Code. A prebuild installs Claude into `/tmp/claude` before a user claims it. That directory belongs to the Pod. It is not part of the home disk.

Step 4 puts the changing owner and workspace name in the Deployment name. A claim replaces the Pod. The new Pod has an empty `/tmp`, so its blocking startup script installs Claude again.

Step 5 names the Deployment with the stable workspace ID. A claim keeps the Pod. Its script finds Claude in `/tmp` and skips the install. This behavior depends on the template. Coder does not replace the Pod for every ordinary prebuild.

| Claim result | Step 4 | Step 5 |
| --- | --- | --- |
| Pod | Replaced | Kept |
| Home disk | Kept | Kept |
| Claude Code | Installed again | Existing install used |
| Measured median | 10.5 s | 1.8 s |

The Step 5 claim saved 8.7 seconds at the median in these six runs. One Step 5 claim took 5.8 seconds because Terraform was slow. Use the trace files to see that variation.

## A short checklist

1. Add `prebuilds` to a preset. Set every immutable parameter in the preset.
2. Keep a node and the image warm. Each prebuild uses a running Pod.
3. Keep the home disk name based on the stable workspace ID.
4. Put files that must survive a Pod replacement on the home disk.
5. If a claim must keep the Pod, keep the owner and workspace name out of its name and labels.
6. Put owner details in annotations. Ignore only their changes during the claim.
7. Make startup scripts safe to run twice. Test the real executable before you skip work.
8. Give user tokens to the workspace after the claim, not to a prebuild.
9. Compare Pod UIDs and script times before and after each claim. Make sure that the agent is healthy.

A stop removes the Pod in both examples. The next start installs Claude again because `/tmp/claude` is gone.

## The Terraform difference

Step 4 uses the owner in a Deployment name. The owner changes from `prebuilds` to the person who claims the workspace.

```tf
locals {
  deployment_name = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
}

resource "kubernetes_deployment_v1" "main" {
  metadata {
    name = local.deployment_name
  }
}
```

Step 5 uses the workspace ID. The ID does not change during a claim.

```tf
locals {
  name = "coder-${data.coder_workspace.me.id}"
}

resource "kubernetes_deployment_v1" "main" {
  metadata {
    name = local.name
    annotations = {
      "com.coder.user.username" = data.coder_workspace_owner.me.name
    }
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}
```

Both snippets omit the Pod specification. Read the full files in `templates/04-standard-prebuilds` and `templates/05-optimized-prebuilds`. They also share the same `claude-startup.sh`.

The deployed Step 4 needed one extra workaround on this Coder development build. It gives the replacement Pod a new agent identity after a claim. Without it, the server marked the new agent as shutting down. This is not a general prebuild setting.
