# Version-controlled Keycloak configuration as Terraform (HCL). The keycloak/keycloak
# provider talks to the admin API and manages realms, clients, scopes and roles as
# resources. Dynamic data (users, sessions) stays in the database.
terraform {
  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = "5.8.0"
    }
  }
}

provider "keycloak" {
  client_id = "admin-cli"
  username  = "admin"
  password  = "admin"
  url       = "http://keycloak:8080"
}

resource "keycloak_realm" "demo" {
  realm        = "demo"
  enabled      = true
  display_name = "Demo Realm"
}

resource "keycloak_openid_client" "demo_app" {
  realm_id                     = keycloak_realm.demo.id
  client_id                    = "demo-app"
  enabled                      = true
  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = true
  valid_redirect_uris          = ["https://demo-app.example.com/*"]
  web_origins                  = ["+"]
  client_secret                = "demo-secret"
}

resource "keycloak_openid_client_scope" "demo_scope" {
  realm_id    = keycloak_realm.demo.id
  name        = "demo-scope"
  description = "Demo client scope"
}

resource "keycloak_role" "demo_role" {
  realm_id    = keycloak_realm.demo.id
  name        = "demo-role"
  description = "Demo realm role"
}
