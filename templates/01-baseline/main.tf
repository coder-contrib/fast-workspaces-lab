terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    http = {
      source = "hashicorp/http"
    }
  }
}

provider "coder" {}
provider "kubernetes" {}
provider "http" {}

variable "namespace" {
  type    = string
  default = "coder-workspaces"
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  name = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  dir  = "/home/coder"

  # Install the tools on every start.
  startup_script_behavior = "blocking"
  startup_script          = <<-EOT
    set -e
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git jq unzip build-essential python3 python3-pip
    # Google Chrome, for browser tests and agents that drive a browser.
    curl -fsSLo /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y /tmp/chrome.deb
    # Go and Node.js toolchains.
    curl -fsSL https://go.dev/dl/go1.25.4.linux-amd64.tar.gz | sudo tar -xz -C /usr/local
    sudo ln -sf /usr/local/go/bin/go /usr/local/bin/go
    sudo ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
    curl -fsSL https://nodejs.org/dist/v22.21.1/node-v22.21.1-linux-x64.tar.xz | sudo tar -xJ -C /usr/local --strip-components=1
    echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/go.sh >/dev/null
    # Cloud and Kubernetes CLIs.
    curl -fsSLo /tmp/awscli.zip https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
    unzip -qo /tmp/awscli.zip -d /tmp && sudo /tmp/aws/install --update
    curl -fsSLo /tmp/kubectl https://dl.k8s.io/release/v1.34.2/bin/linux/amd64/kubectl
    sudo install -m 755 /tmp/kubectl /usr/local/bin/kubectl
    # JavaScript tools and a browser for Playwright tests.
    sudo npm install -g pnpm typescript playwright
    playwright install chromium
    curl -fsSL https://claude.ai/install.sh | bash
  EOT

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
  agent_id = coder_agent.main.id
  folder   = "/home/coder"
}

module "git-clone" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-clone/coder"
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
    bin=/opt/claude/bin/claude
    [ -x "$bin" ] || bin="$HOME/.local/bin/claude"
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
    name      = local.name
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"   = "coder-workspace"
      "com.coder.user.username"  = data.coder_workspace_owner.me.name
      "com.coder.workspace.name" = data.coder_workspace.me.name
    }
  }
  wait_for_rollout = true
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
        container {
          name  = "dev"
          image = "ubuntu:24.04"
          # A plain image: install curl and sudo, create the user, then
          # download and start the Coder agent.
          command = ["sh", "-c", <<-EOT
            set -e
            apt-get update
            DEBIAN_FRONTEND=noninteractive apt-get install -y curl sudo ca-certificates git xz-utils
            id coder >/dev/null 2>&1 || useradd -m -s /bin/bash coder
            echo "coder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/coder
            chown coder:coder /home/coder
            exec su coder -c '${replace(coder_agent.main.init_script, "'", "'\\''")}'
          EOT
          ]
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
