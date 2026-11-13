# Keep a node ready

A node is a VM that runs workspace Pods. A workspace waits for a new node if every ready node is full. The five measured runs used one ready node. They did not include node startup time.

Give a node the `coder.com/pool=speed` label before you start a workspace. The templates select that label. `cluster/prepull.yaml` pulls the full image onto that node. `cluster/prepull-claim.yaml` pulls the image without Claude Code.

The baseline has no pre-pull DaemonSet. Its Ubuntu image was already cached from earlier use. A new tag or `imagePullPolicy: Always` does not guarantee a full download on every start. To measure a cold pull, use a fresh node or an image that has never been present there.

`cluster/node-schedule.tf` is an optional EKS example. It keeps one managed node group node ready at 9 AM on weekdays. The time zone is `America/New_York`. Change the group name and region for your cluster.

Do not enable its 5 PM scale-down while workspaces or prebuilds still use the node. The action sets desired capacity to zero. Coder prebuilds must stop on their own schedule before that action.

A warm node costs money even when it runs no workspace. A prebuild also uses a running Pod. Keep enough capacity for the people who use the pool.
