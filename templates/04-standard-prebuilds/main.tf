terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

provider "coder" {}
provider "kubernetes" {}
provider "http" {}

variable "image" {
  type    = string
  default = "registry.example.com/coder/workspace:no-claude-v1"
}

variable "namespace" {
  type    = string
  default = "coder-workspaces"
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

variable "prebuild_instances" {
  type    = number
  default = 2
}

# A preset with prebuilds. Coder keeps this many workspaces built and
# running, and a new workspace claims one of them.
data "coder_workspace_preset" "default" {
  name    = "Default"
  default = true
  prebuilds {
    instances = var.prebuild_instances
    # Replace a prebuild that nobody claims within a day, so it does not
    # run an old image or a stale clone for long.
    expiration_policy {
      ttl = 86400
    }
  }
}

locals {
  # The workspace ID is stable across a claim, so its home disk persists.
  name = "coder-${data.coder_workspace.me.id}"
  # This common owner-dependent name changes from prebuilds/<random> to the
  # new owner and name when claimed. Kubernetes replaces the Deployment Pod.
  deployment_name = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
}

resource "terraform_data" "agent_owner" {
  triggers_replace = data.coder_workspace_owner.me.id
}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  dir  = "/home/coder"

  # A replacement Pod must get a new agent identity. Otherwise the claim's
  # reinitialization can reach a new process with the old agent's identity.
  lifecycle {
    replace_triggered_by = [terraform_data.agent_owner]
  }

  # The prebuild installs Claude into the Pod filesystem. A replacement Pod
  # loses the install and must run this blocking script again on claim.
  startup_script_behavior = "blocking"
  startup_script          = file("${path.module}/claude-startup.sh")

  metadata {
    display_name = "CPU Usage"
    key          = "cpu"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }
}

module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "1.6.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder"
  # code-server is in the image, so the module downloads nothing.
  offline        = true
  install_prefix = "/opt/code-server"
}

# A prebuild clones the repository before anyone claims it. The module
# skips the clone when the folder exists, so a claim does not wait for it.
module "git-clone" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "2.0.5"
  agent_id = coder_agent.main.id
  url      = "https://github.com/coder/registry"
  base_dir = "/home/coder"
}

# Give Claude Code a scoped token for the Coder AI Gateway. Do not put the
# workspace owner's full session token in the agent or in a prebuild.
locals {
  mint_ai_gateway_token = (
    data.coder_workspace.me.start_count > 0 &&
    !data.coder_workspace.me.is_prebuild &&
    data.coder_workspace_owner.me.session_token != ""
  )
}

data "http" "ai_gateway_token" {
  count  = local.mint_ai_gateway_token ? 1 : 0
  url    = "${data.coder_workspace.me.access_url}/api/v2/users/me/keys/tokens"
  method = "POST"
  request_headers = {
    "Coder-Session-Token" = data.coder_workspace_owner.me.session_token
    "Content-Type"        = "application/json"
  }
  request_body = jsonencode({
    token_name = "speed-ai-gateway-${substr(data.coder_workspace.me.id, 0, 8)}-${formatdate("YYYYMMDDhhmmss", timestamp())}"
    scopes     = ["user:read_personal"]
  })
  lifecycle {
    postcondition {
      condition     = self.status_code == 201
      error_message = "Could not create the AI Gateway token: HTTP ${self.status_code}."
    }
  }
}

resource "coder_env" "anthropic_base_url" {
  count    = data.coder_workspace.me.start_count
  agent_id = coder_agent.main.id
  name     = "ANTHROPIC_BASE_URL"
  value    = "${data.coder_workspace.me.access_url}/api/v2/aibridge/anthropic"
}

resource "coder_env" "anthropic_auth_token" {
  count    = local.mint_ai_gateway_token ? 1 : 0
  agent_id = coder_agent.main.id
  name     = "ANTHROPIC_AUTH_TOKEN"
  value    = sensitive(jsondecode(data.http.ai_gateway_token[0].response_body).key)
}

resource "coder_app" "claude" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  slug         = "claude-code"
  display_name = "Claude Code"
  icon         = "/icon/claude.svg"
  order        = 2
  command      = <<-EOT
    cd /home/coder
    bin=/tmp/claude/.local/bin/claude
    "$bin" --continue || exec "$bin"
  EOT
}

resource "kubernetes_persistent_volume_claim_v1" "home" {
  metadata {
    name      = "${local.name}-home"
    namespace = var.namespace
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = { storage = "10Gi" }
    }
  }
}

resource "kubernetes_deployment_v1" "main" {
  count = data.coder_workspace.me.start_count
  metadata {
    name      = local.deployment_name
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name" = "coder-workspace"
      "com.coder.workspace.id" = data.coder_workspace.me.id
    }
    # The owner is useful in kubectl, but it changes on a claim, so the
    # claim must not update it.
    annotations = {
      "com.coder.user.username"  = data.coder_workspace_owner.me.name
      "com.coder.workspace.name" = data.coder_workspace.me.name
    }
  }
  # The agent reports when the workspace is ready, so the build does not
  # need to wait for the rollout.
  wait_for_rollout = false
  spec {
    replicas = 1
    selector {
      match_labels = { "com.coder.workspace.id" = data.coder_workspace.me.id }
    }
    strategy {
      type = "Recreate"
    }
    template {
      metadata {
        labels = { "com.coder.workspace.id" = data.coder_workspace.me.id }
      }
      spec {
        # The demo runs on one node: the ng-speed node group.
        node_selector = { "coder.com/pool" = "speed" }
        toleration {
          key      = "coder.com/pool"
          operator = "Equal"
          value    = "speed"
          effect   = "NoSchedule"
        }
        security_context {
          run_as_user = 1000
          fs_group    = 1000
        }
        container {
          name = "dev"
          # Built from build/Dockerfile: the Coder agent, code-server, and
          # Claude Code are in the image, so a start downloads nothing.
          image             = var.image
          image_pull_policy = "IfNotPresent"
          command           = ["/usr/local/bin/coder", "agent"]
          env {
            name  = "CODER_AGENT_URL"
            value = data.coder_workspace.me.access_url
          }
          env {
            name  = "CODER_AGENT_AUTH"
            value = "token"
          }
          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }
          resources {
            requests = { cpu = "250m", memory = "1Gi" }
            limits   = { cpu = "2", memory = "4Gi" }
          }
          volume_mount {
            mount_path = "/home/coder"
            name       = "home"
          }
        }
        volume {
          name = "home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.home.metadata[0].name
          }
        }
      }
    }
  }
}
