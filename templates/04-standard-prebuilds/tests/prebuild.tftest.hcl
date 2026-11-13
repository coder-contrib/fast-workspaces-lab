mock_provider "coder" {
  mock_data "coder_workspace" {
    defaults = {
      id          = "0b6b6a5e-0000-4000-8000-000000000001"
      name        = "prebuild-example"
      start_count = 1
      access_url  = "https://coder.example.com"
      is_prebuild = true
    }
  }
  mock_data "coder_workspace_owner" {
    defaults = {
      id            = "0b6b6a5e-0000-4000-8000-000000000002"
      name          = "prebuilds"
      session_token = ""
    }
  }
}

mock_provider "kubernetes" {}
mock_provider "http" {}

override_module {
  target  = module.code-server
  outputs = {}
}

override_module {
  target  = module.git-clone
  outputs = {}
}

run "prebuild" {
  command = plan

  assert {
    condition     = kubernetes_deployment_v1.main[0].metadata[0].name == "coder-prebuilds-prebuild-example"
    error_message = "A prebuild must name the Deployment after its current owner and name."
  }
  assert {
    condition     = kubernetes_persistent_volume_claim_v1.home.metadata[0].name == "coder-0b6b6a5e-0000-4000-8000-000000000001-home"
    error_message = "The home disk must use the stable workspace ID."
  }
  assert {
    condition     = coder_agent.main.startup_script_behavior == "blocking" && strcontains(coder_agent.main.startup_script, "/tmp/claude/.local/bin/claude") && strcontains(coder_app.claude[0].command, "/tmp/claude/.local/bin/claude")
    error_message = "The prebuild must install Claude in the Pod filesystem before it is ready."
  }
}

run "claimed" {
  command = plan

  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "0b6b6a5e-0000-4000-8000-000000000001"
      name        = "claimed-example"
      start_count = 1
      access_url  = "https://coder.example.com"
      is_prebuild = false
    }
  }
  override_data {
    target = data.coder_workspace_owner.me
    values = {
      id            = "0b6b6a5e-0000-4000-8000-000000000003"
      name          = "alice"
      session_token = ""
    }
  }

  assert {
    condition     = kubernetes_deployment_v1.main[0].metadata[0].name == "coder-alice-claimed-example"
    error_message = "The claim must change the Deployment name and replace its Pod."
  }
  assert {
    condition     = kubernetes_persistent_volume_claim_v1.home.metadata[0].name == "coder-0b6b6a5e-0000-4000-8000-000000000001-home"
    error_message = "The claim must keep the same home disk."
  }
}
