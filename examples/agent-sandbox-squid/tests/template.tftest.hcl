mock_provider "coder" {
  mock_data "coder_workspace" {
    defaults = {
      id          = "0b6b6a5e-0000-4000-8000-000000000001"
      name        = "test"
      start_count = 1
      transition  = "start"
      access_url  = "https://203.0.113.10"
    }
  }
  mock_data "coder_workspace_owner" {
    defaults = {
      id            = "0b6b6a5e-0000-4000-8000-000000000002"
      name          = "owner"
      email         = "owner@example.org"
      session_token = "owner-full-session-token"
    }
  }
}

mock_provider "kubernetes" {}

mock_provider "http" {
  mock_data "http" {
    defaults = {
      status_code   = 201
      response_body = "{\"key\":\"scoped-id-scoped-secret\"}"
    }
  }
}

override_module {
  target  = module.code-server
  outputs = {}
}

override_module {
  target  = module.git-clone
  outputs = {}
}

variables {
  coder_egress_cidrs = ["203.0.113.10/32"]
}

override_data {
  target = data.coder_parameter.network_isolation
  values = { value = "isolated" }
}

override_data {
  target = data.coder_parameter.runtime
  values = { value = "gvisor" }
}

override_resource {
  target          = terraform_data.pod_name
  override_during = plan
  values          = { id = "1a2b3c4d-0000-4000-8000-000000000003" }
}

run "defaults" {
  command = plan

  assert {
    condition     = var.namespace == "coder-workspaces" && var.image == "registry.example.com/coder/workspace:speed-v1" && var.proxy_image == "registry.example.com/coder/squid:7.6"
    error_message = "The namespace and images must use the public example defaults."
  }
  assert {
    condition     = [for o in data.coder_parameter.runtime.option : o.value] == ["gvisor"] && data.coder_parameter.runtime.default == "gvisor"
    error_message = "gVisor must be the default runtime."
  }
}

run "additional_runtime_classes" {
  command = plan

  variables {
    runtimes = "gvisor,kata-fc,edera,custom.vm"
  }

  override_data {
    target = data.coder_parameter.runtime
    values = { value = "custom.vm" }
  }

  assert {
    condition     = [for o in data.coder_parameter.runtime.option : o.value] == ["gvisor", "kata-fc", "edera", "custom.vm"] && data.coder_parameter.runtime.default == "gvisor"
    error_message = "Installed RuntimeClasses must be available, with the fastest one first."
  }
  assert {
    condition     = kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.runtimeClassName == "custom.vm"
    error_message = "The selected RuntimeClass must reach the Sandbox Pod."
  }
}

run "controller_managed_sandbox" {
  command = plan

  assert {
    condition     = length(kubernetes_manifest.sandbox) == 1 && kubernetes_manifest.sandbox[0].manifest.apiVersion == "agents.x-k8s.io/v1beta1" && kubernetes_manifest.sandbox[0].manifest.kind == "Sandbox"
    error_message = "The workspace must be an agent-sandbox Sandbox."
  }
  assert {
    condition     = kubernetes_manifest.sandbox[0].manifest.spec.shutdownPolicy == "Delete" && kubernetes_manifest.sandbox[0].manifest.metadata.namespace == "coder-workspaces"
    error_message = "The Sandbox must be in the namespace and delete its Pod on shutdown."
  }
  assert {
    condition     = kubernetes_manifest.sandbox[0].manifest.metadata.name == "coder-0b6b6a5e-0000-4000-8000-000000000001-1a2b3c4d-pod"
    error_message = "Sandbox names must end in -pod, after a part that is new for every start."
  }
  assert {
    condition     = kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.runtimeClassName == "gvisor"
    error_message = "The runtime parameter must set the RuntimeClass."
  }
  assert {
    condition     = kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.nodeSelector["coder.com/pool"] == "speed"
    error_message = "The Sandbox Pod must run on the speed node group."
  }
  assert {
    condition = jsonencode(kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.tolerations) == jsonencode([{
      effect   = "NoSchedule"
      key      = "coder.com/pool"
      operator = "Equal"
      value    = "speed"
    }])
    error_message = "The Sandbox Pod must tolerate the speed node group taint."
  }
  assert {
    condition     = length(kubernetes_pod_v1.proxy) == 0
    error_message = "Fully isolated must create no proxy Pod."
  }
  assert {
    condition = alltrue([
      kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.automountServiceAccountToken == false,
      kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.enableServiceLinks == false,
      kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.securityContext.runAsNonRoot == true,
      kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.securityContext.runAsUser == 1000,
      kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.securityContext.fsGroup == 1000,
      kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.securityContext.seccompProfile.type == "RuntimeDefault",
      kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].securityContext.allowPrivilegeEscalation == false,
      kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].securityContext.capabilities.drop[0] == "ALL",
      kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].imagePullPolicy == "IfNotPresent",
      kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].image == var.image,
    ])
    error_message = "The Sandbox Pod must be hardened and run the workspace image."
  }
  assert {
    condition     = kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].env[0].valueFrom.secretKeyRef.name == kubernetes_secret_v1.agent_token[0].metadata[0].name && kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].env[1].value == "https://203.0.113.10"
    error_message = "The agent token must come from the Secret, and CODER_AGENT_URL must be the access URL."
  }
  assert {
    condition     = strcontains(kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].command[2], "exec /usr/local/bin/coder agent\n") && strcontains(kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].command[2], "KUBERNETES_SERVICE_HOST") && startswith(kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].command[2], "[ -e /home/coder/.bashrc ] || cp -an /etc/skel/.")
    error_message = "The container must seed the home, run the policy gate, and then the agent from the image."
  }
  assert {
    condition     = jsonencode(kubernetes_manifest.sandbox[0].manifest.metadata.labels) == jsonencode(local.labels) && !strcontains(jsonencode(kubernetes_manifest.sandbox[0].manifest), "owner")
    error_message = "The Sandbox must not depend on the owner, so a prebuild claim does not replace it."
  }
}

run "persistent_home" {
  command = plan

  assert {
    condition     = kubernetes_persistent_volume_claim_v1.home.metadata[0].name == "coder-0b6b6a5e-0000-4000-8000-000000000001-home" && kubernetes_persistent_volume_claim_v1.home.spec[0].resources[0].requests.storage == "10Gi" && kubernetes_persistent_volume_claim_v1.home.wait_until_bound == false
    error_message = "The home must be a 10Gi PVC that the build does not wait for."
  }
  assert {
    condition     = kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.volumes[0].persistentVolumeClaim.claimName == kubernetes_persistent_volume_claim_v1.home.metadata[0].name && kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].volumeMounts[0].mountPath == "/home/coder"
    error_message = "The Sandbox must mount the PVC at /home/coder."
  }
  assert {
    condition     = !can(kubernetes_manifest.sandbox[0].manifest.spec.volumeClaimTemplates)
    error_message = "Coder must own the disk, not the Sandbox, so it outlives a stop."
  }
}

run "stop_keeps_home" {
  command = plan

  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "0b6b6a5e-0000-4000-8000-000000000001"
      name        = "test"
      start_count = 0
      transition  = "stop"
      access_url  = "https://203.0.113.10"
    }
  }
  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "github" }
  }

  assert {
    condition     = length(kubernetes_manifest.sandbox) == 0 && length(kubernetes_pod_v1.proxy) == 0 && length(kubernetes_secret_v1.agent_token) == 0
    error_message = "Stop must delete the Sandbox, the proxy Pod, and the token."
  }
  assert {
    condition     = kubernetes_persistent_volume_claim_v1.home.metadata[0].name == "coder-0b6b6a5e-0000-4000-8000-000000000001-home" && length(kubernetes_service_v1.proxy) == 1
    error_message = "Stop must keep the home disk and the proxy Service."
  }
}

run "isolated_network" {
  command = plan

  assert {
    condition     = length(kubernetes_service_v1.proxy) == 0 && length(kubernetes_network_policy_v1.proxy) == 0 && length(kubernetes_config_map_v1.proxy) == 0
    error_message = "Fully isolated must have no proxy."
  }
  assert {
    condition     = jsonencode(kubernetes_network_policy_v1.workspace.spec[0].pod_selector[0].match_labels) == jsonencode(kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.metadata.labels) && kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.metadata.labels["coder.com/role"] == "workspace"
    error_message = "The workspace NetworkPolicy must select the labels on the Sandbox podTemplate."
  }
  assert {
    condition     = length(kubernetes_network_policy_v1.workspace.spec[0].egress) == 1 && [for t in kubernetes_network_policy_v1.workspace.spec[0].egress[0].to : t.ip_block[0].cidr] == ["203.0.113.10/32"] && [for p in kubernetes_network_policy_v1.workspace.spec[0].egress[0].ports : p.port] == ["443"]
    error_message = "Fully isolated must allow only the Coder server on 443."
  }
  assert {
    condition     = length(kubernetes_network_policy_v1.workspace.spec[0].ingress) == 0 && kubernetes_network_policy_v1.workspace.spec[0].policy_types == tolist(["Ingress", "Egress"])
    error_message = "The workspace must get no ingress."
  }
  assert {
    condition     = kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.dnsPolicy == "None" && jsonencode(kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.dnsConfig.nameservers) == jsonencode(["127.0.0.1"])
    error_message = "The workspace must have no DNS, and lookups must fail at once."
  }
  assert {
    condition     = length(kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].env) == 3
    error_message = "Fully isolated must set no proxy variables."
  }
  assert {
    condition     = !can(kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.hostAliases)
    error_message = "An IP access URL needs no host alias."
  }
  assert {
    condition     = length(module.git-clone) == 0
    error_message = "Fully isolated cannot reach GitHub, so it must not clone."
  }
}

run "github_network" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "github" }
  }

  assert {
    condition     = length(kubernetes_pod_v1.proxy) == 1 && length(kubernetes_service_v1.proxy) == 1 && length(kubernetes_config_map_v1.proxy) == 1
    error_message = "GitHub only must create a separate proxy Pod and Service."
  }
  assert {
    condition = (
      length(kubernetes_network_policy_v1.workspace.spec[0].egress) == 2 &&
      [for t in kubernetes_network_policy_v1.workspace.spec[0].egress[0].to : t.ip_block[0].cidr] == ["203.0.113.10/32"] &&
      [for p in kubernetes_network_policy_v1.workspace.spec[0].egress[0].ports : p.port] == ["443"] &&
      length(kubernetes_network_policy_v1.workspace.spec[0].egress[1].to) == 1 &&
      kubernetes_network_policy_v1.workspace.spec[0].egress[1].to[0].pod_selector[0].match_labels == kubernetes_pod_v1.proxy[0].metadata[0].labels &&
      length(kubernetes_network_policy_v1.workspace.spec[0].egress[1].to[0].ip_block) == 0 &&
      [for p in kubernetes_network_policy_v1.workspace.spec[0].egress[1].ports : p.port] == ["3128"]
    )
    error_message = "The workspace must reach only Coder on 443 and its own proxy on 3128. No DNS and no direct public route."
  }
  assert {
    condition     = jsonencode(kubernetes_network_policy_v1.proxy[0].spec[0].ingress[0].from[0].pod_selector[0].match_labels) == jsonencode(kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.metadata.labels)
    error_message = "Only the Sandbox Pod must reach the proxy."
  }
  assert {
    condition = (
      kubernetes_network_policy_v1.proxy[0].spec[0].egress[0].to[0].ip_block[0].cidr == "0.0.0.0/0" &&
      alltrue([for c in ["10.0.0.0/8", "100.64.0.0/10", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16"] : contains(kubernetes_network_policy_v1.proxy[0].spec[0].egress[0].to[0].ip_block[0].except, c)]) &&
      [for p in kubernetes_network_policy_v1.proxy[0].spec[0].egress[0].ports : p.port] == ["443"]
    )
    error_message = "The proxy must reach only public addresses on 443, with no private ranges."
  }
  assert {
    condition     = [for t in kubernetes_network_policy_v1.proxy[0].spec[0].egress[1].to : t.ip_block[0].cidr] == ["8.8.8.8/32", "1.1.1.1/32"] && [for p in kubernetes_network_policy_v1.proxy[0].spec[0].egress[1].ports : p.port] == ["53", "53"]
    error_message = "The proxy must reach only public DNS on port 53."
  }
  assert {
    condition     = strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "acl allowed dstdomain -n github.com api.github.com") && !strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "registry.npmjs.org") && strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "http_access deny !CONNECT\n")
    error_message = "GitHub only must allow the GitHub hosts over HTTPS only."
  }
  assert {
    condition     = [for e in kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].env : e.name] == ["CODER_AGENT_TOKEN", "CODER_AGENT_URL", "CODER_AGENT_AUTH", "HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "no_proxy"]
    error_message = "The Sandbox Pod must get the proxy variables."
  }
  assert {
    condition     = local.proxy_env["no_proxy"] == "localhost,127.0.0.1,::1,203.0.113.10"
    error_message = "The workspace must reach Coder without the proxy."
  }
  assert {
    condition = alltrue([
      kubernetes_pod_v1.proxy[0].spec[0].automount_service_account_token == false,
      kubernetes_pod_v1.proxy[0].spec[0].security_context[0].run_as_user == "31",
      kubernetes_pod_v1.proxy[0].spec[0].container[0].security_context[0].read_only_root_filesystem == true,
      kubernetes_pod_v1.proxy[0].spec[0].container[0].security_context[0].capabilities[0].drop[0] == "ALL",
      kubernetes_pod_v1.proxy[0].spec[0].container[0].image == var.proxy_image,
      kubernetes_pod_v1.proxy[0].spec[0].node_selector["coder.com/pool"] == "speed",
      kubernetes_pod_v1.proxy[0].spec[0].toleration[0].effect == "NoSchedule",
      kubernetes_pod_v1.proxy[0].spec[0].runtime_class_name == null,
    ])
    error_message = "The proxy Pod must be hardened, run on the speed nodes, and use the node's container runtime."
  }
  assert {
    condition     = kubernetes_pod_v1.proxy[0].metadata[0].name == "coder-0b6b6a5e-0000-4000-8000-000000000001-proxy-1a2b3c4d-pod"
    error_message = "Proxy Pod names must end in -pod, after a part that is new for every start."
  }
  assert {
    condition     = length(module.git-clone) == 1
    error_message = "GitHub only must clone git_repo_url."
  }
}

run "internet_network" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "internet" }
  }

  assert {
    condition     = strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "dstdom_regex -n -i [a-z]$") && strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "http_access allow allowed !private_dst")
    error_message = "Public internet must allow any host name but no private address."
  }
  assert {
    condition     = [for p in kubernetes_network_policy_v1.proxy[0].spec[0].egress[0].ports : p.port] == ["443", "80"] && length(kubernetes_network_policy_v1.workspace.spec[0].egress) == 2
    error_message = "Public internet must let the proxy use 443 and 80, and the workspace still only Coder and the proxy."
  }
}

run "custom" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "custom" }
  }
  override_data {
    target = data.coder_parameter.custom_hosts
    values = { value = "[\"Example.com\", \" *.wikipedia.org \", \"example.com\"]" }
  }
  override_data {
    target = data.coder_parameter.custom_ports
    values = { value = "[\"443\", \"80\"]" }
  }

  assert {
    condition     = strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "acl allowed dstdomain -n example.com .wikipedia.org\n")
    error_message = "Custom must allow the typed hosts once each, in lowercase, with *. written as a leading dot."
  }
  assert {
    condition     = length(data.coder_parameter.custom_problems) == 0 && length(terraform_data.custom_check) == 1
    error_message = "Valid Custom fields must show no problems."
  }
  assert {
    condition     = [for p in kubernetes_network_policy_v1.proxy[0].spec[0].egress[0].ports : p.port] == ["443", "80"]
    error_message = "The proxy must reach only the picked ports."
  }
  assert {
    condition     = length(module.git-clone) == 0
    error_message = "Custom must not clone, because it may not allow GitHub."
  }
}

run "custom_rejects_ip_and_cluster_names" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "custom" }
  }
  override_data {
    target = data.coder_parameter.custom_hosts
    values = { value = "[\"1.2.3.4\", \"kubernetes.default.svc\", \"*.com\", \"metadata.google.internal\"]" }
  }
  override_data {
    target = data.coder_parameter.custom_ports
    values = { value = "[\"443\"]" }
  }

  expect_failures = [terraform_data.custom_check]
}

run "custom_problems_shows_bad_hosts" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "custom" }
  }
  override_data {
    target = data.coder_parameter.custom_hosts
    values = { value = "[\"example.com\", \"1.2.3.4\", \"foo.svc\"]" }
  }
  override_data {
    target = data.coder_parameter.custom_ports
    values = { value = "[\"443\"]" }
  }

  expect_failures = [terraform_data.custom_check]

  assert {
    condition     = local.custom_bad == ["1.2.3.4", "foo.svc"] && local.custom_problems == 2
    error_message = "Custom must list each host that is not valid."
  }
}

run "custom_needs_a_host" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "custom" }
  }
  override_data {
    target = data.coder_parameter.custom_hosts
    values = { value = "[\" \"]" }
  }
  override_data {
    target = data.coder_parameter.custom_ports
    values = { value = "[\"443\"]" }
  }

  expect_failures = [terraform_data.custom_check]
}

run "custom_needs_a_port" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "custom" }
  }
  override_data {
    target = data.coder_parameter.custom_hosts
    values = { value = "[\"example.com\"]" }
  }
  override_data {
    target = data.coder_parameter.custom_ports
    values = { value = "[]" }
  }

  expect_failures = [terraform_data.custom_check]
}

run "custom_http_only" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "custom" }
  }
  override_data {
    target = data.coder_parameter.custom_hosts
    values = { value = "[\"example.com\"]" }
  }
  override_data {
    target = data.coder_parameter.custom_ports
    values = { value = "[\"80\", \"80\"]" }
  }

  assert {
    condition     = strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "http_access deny CONNECT\n") && !strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "http_access deny !CONNECT\n")
    error_message = "Custom with port 80 only must deny HTTPS tunnels and allow plain HTTP."
  }
  assert {
    condition     = [for p in kubernetes_network_policy_v1.proxy[0].spec[0].egress[0].ports : p.port] == ["80"]
    error_message = "The proxy must reach only port 80, once."
  }
}

run "presets" {
  command = plan

  assert {
    condition     = keys(data.coder_workspace_preset.profile) == ["development", "github", "internet", "isolated"]
    error_message = "Every fixed profile must have a preset, and Custom none."
  }
  assert {
    condition     = data.coder_workspace_preset.profile["isolated"].default == true && data.coder_workspace_preset.profile["github"].default == false
    error_message = "Fully isolated must be the default preset."
  }
  assert {
    condition     = alltrue([for k, p in data.coder_workspace_preset.profile : p.parameters.network_isolation == k && p.parameters.runtime == "gvisor"])
    error_message = "Presets must set every immutable parameter, so a claim does not change one."
  }
  assert {
    condition     = length(data.coder_workspace_preset.profile["isolated"].prebuilds) == 1 && one(data.coder_workspace_preset.profile["isolated"].prebuilds).instances == 1 && one(one(data.coder_workspace_preset.profile["isolated"].prebuilds).expiration_policy).ttl == 86400 && alltrue([for k, p in data.coder_workspace_preset.profile : length(p.prebuilds) == 0 if k != "isolated"])
    error_message = "Only the default preset must keep one prebuild, which expires after a day."
  }
}

run "no_prebuilds" {
  command = plan

  variables {
    prebuild_instances = 0
  }

  assert {
    condition     = alltrue([for p in data.coder_workspace_preset.profile : length(p.prebuilds) == 0])
    error_message = "prebuild_instances = 0 must turn prebuilds off."
  }
}

run "rejects_multiple_prebuilds" {
  command = plan

  variables {
    prebuild_instances = 2
  }

  expect_failures = [var.prebuild_instances]
}

run "host_name_needs_ip" {
  command = plan

  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "0b6b6a5e-0000-4000-8000-000000000001"
      name        = "test"
      start_count = 1
      transition  = "start"
      access_url  = "https://coder.example.com"
    }
  }

  expect_failures = [kubernetes_manifest.sandbox]
}

run "host_name_alias" {
  command = plan

  variables {
    coder_host_ip = "203.0.113.10"
  }
  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "0b6b6a5e-0000-4000-8000-000000000001"
      name        = "test"
      start_count = 1
      transition  = "start"
      access_url  = "https://coder.example.com"
    }
  }
  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "github" }
  }

  assert {
    condition     = kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.hostAliases[0].ip == "203.0.113.10" && kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.hostAliases[0].hostnames[0] == "coder.example.com"
    error_message = "A host name access URL must map to coder_host_ip."
  }
  assert {
    condition     = local.proxy_env["NO_PROXY"] == "localhost,127.0.0.1,::1,coder.example.com"
    error_message = "The agent must reach Coder without the proxy."
  }
}

run "port_from_access_url" {
  command = plan

  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "0b6b6a5e-0000-4000-8000-000000000001"
      name        = "test"
      start_count = 1
      transition  = "start"
      access_url  = "http://203.0.113.10:8080"
    }
  }

  assert {
    condition     = kubernetes_network_policy_v1.workspace.spec[0].egress[0].ports[0].port == "8080"
    error_message = "The Coder port must come from the access URL."
  }
}

run "no_policy_gate" {
  command = plan

  variables {
    network_policy_gate = false
  }

  assert {
    condition     = endswith(kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].command[2], "\nexec /usr/local/bin/coder agent") && !strcontains(kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].command[2], "KUBERNETES_SERVICE_HOST")
    error_message = "network_policy_gate = false must start the agent at once."
  }
}

run "code_server_and_claude" {
  command = plan

  assert {
    condition     = length(module.code-server) == 1 && length(coder_app.claude) == 1 && coder_app.claude[0].slug == "claude-code"
    error_message = "The workspace must have code-server and the Claude Code app."
  }
}

run "ai_gateway_scoped_token" {
  command = apply

  assert {
    condition     = nonsensitive(coder_env.anthropic_auth_token[0].value) == "scoped-id-scoped-secret" && coder_env.anthropic_base_url[0].value == "https://203.0.113.10/api/v2/aibridge/anthropic"
    error_message = "Claude Code must get the scoped token and the AI Gateway URL, not the owner's session token."
  }
  assert {
    condition     = jsonencode(jsondecode(data.http.ai_gateway_token[0].request_body).scopes) == jsonencode(["user:read_personal"]) && nonsensitive(data.http.ai_gateway_token[0].request_headers["Coder-Session-Token"]) == "owner-full-session-token"
    error_message = "The build must create a token with only the user:read_personal scope, using the owner's session token."
  }
}

run "ai_gateway_prebuild" {
  command = plan

  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "0b6b6a5e-0000-4000-8000-000000000001"
      name        = "test"
      start_count = 1
      transition  = "start"
      access_url  = "https://203.0.113.10"
      is_prebuild = true
    }
  }

  assert {
    condition     = length(data.http.ai_gateway_token) == 0 && length(coder_env.anthropic_auth_token) == 0
    error_message = "A prebuild must not create a token. The claim does."
  }
}

run "rejects_latest_image" {
  command = plan

  variables {
    image = "registry.example.com/coder/workspace:latest"
  }

  expect_failures = [var.image]
}

run "rejects_untagged_proxy_image" {
  command = plan

  variables {
    proxy_image = "registry.example.com/coder/egress-proxy"
  }

  expect_failures = [var.proxy_image]
}

run "rejects_invalid_runtime" {
  command = plan

  variables {
    runtimes = "gvisor,!bad"
  }

  expect_failures = [var.runtimes]
}

run "rejects_ipv6_cidr" {
  command = plan

  variables {
    coder_egress_cidrs = ["2001:db8::/64"]
  }

  expect_failures = [var.coder_egress_cidrs]
}
