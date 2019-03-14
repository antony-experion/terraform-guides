terraform {
  required_version = ">= 0.11.11"
}

resource "vault_auth_backend" "k8s" {
  type = "kubernetes"
  path = "${data.terraform_remote_state.k8s_cluster.vault_user}-gke-${data.terraform_remote_state.k8s_cluster.environment}"
  description = "Vault Auth backend for Kubernetes"
}

provider "vault" {
  address = "${data.terraform_remote_state.k8s_cluster.vault_addr}"
}

data "terraform_remote_state" "k8s_cluster" {
  backend = "atlas"
  config {
    name = "${var.tfe_organization}/${var.k8s_cluster_workspace}"
  }
}

provider "kubernetes" {
  host = "${data.terraform_remote_state.k8s_cluster.k8s_endpoint}"
  client_certificate = "${base64decode(data.terraform_remote_state.k8s_cluster.k8s_master_auth_client_certificate)}"
  client_key = "${base64decode(data.terraform_remote_state.k8s_cluster.k8s_master_auth_client_key)}"
  cluster_ca_certificate = "${base64decode(data.terraform_remote_state.k8s_cluster.k8s_master_auth_cluster_ca_certificate)}"
}

resource "kubernetes_service_account" "vault-reviewer" {
  metadata {
    name = "vault-reviewer"
  }
}

data "kubernetes_secret" "vault-reviewer-token" {
  metadata {
    name = "${kubernetes_service_account.vault-reviewer.default_secret_name}"
  }
}

# Use the vault_kubernetes_auth_backend_config resource
# instead of the a curl command in local-exec
resource "vault_kubernetes_auth_backend_config" "auth_config" {
  backend = "${vault_auth_backend.k8s.path}"
  kubernetes_host = "https://${data.terraform_remote_state.k8s_cluster.k8s_endpoint}:443"
  kubernetes_ca_cert = "${chomp(base64decode(data.terraform_remote_state.k8s_cluster.k8s_master_auth_cluster_ca_certificate))}"
  token_reviewer_jwt = "${data.kubernetes_secret.vault-reviewer-token.data.token}"
}

# Use vault_kubernetes_auth_backend_role instead of
# vault_generic_secret
resource "vault_kubernetes_auth_backend_role" "role" {
  backend = "${vault_auth_backend.k8s.path}"
  role_name = "demo"
  bound_service_account_names = ["cats-and-dogs"]
  bound_service_account_namespaces = ["default", "cats-and-dogs"]
  policies = ["${data.terraform_remote_state.k8s_cluster.vault_user}"]
  ttl = 7200
}
