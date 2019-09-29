#!/bin/bash
set -euf -o pipefail

#####################################
# CONFIGURANDO MYSQL SECRETs ENGINE #
#####################################

export VAULT_ADDR=$(minikube service vault-server --url)

# valor padrão em dev mode no Helm Chart
export VAULT_TOKEN=root 

#####################################
# CONFIGURANDO MYSQL SECRETs ENGINE #
#####################################

vault secrets enable database 	

vault write database/config/meu-banco \
    plugin_name=mysql-database-plugin \
    connection_url="{{username}}:{{password}}@tcp(meu-banco:3306)/" \
    username="root" \
    password="root"

vault write database/roles/read \
    db_name=meu-banco \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT SELECT ON *.* TO '{{name}}'@'%';" \
    default_ttl="1h" \
    max_ttl="24h"

vault write database/roles/crud \
    db_name=meu-banco \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT SELECT, CREATE, INSERT, UPDATE, DELETE, LOCK TABLES, REFERENCES
 ON *.* TO '{{name}}'@'%';" \
    default_ttl="1h" \
    max_ttl="24h"

#########################
# CONFIGURANDO POLICIES #
#########################

# DEV policy: acesso a ROLE 'read'
cat <<EOF | vault policy write dev - 
path "/database/meu-banco/read" {
    capabilities = ["read", "list"]
}
EOF

# APP policy: acesso a ROLE 'crud'
cat <<EOF | vault policy write app - 
path "/database/meu-banco/crud" {
    capabilities = ["read", "list"]
}
EOF

#############################
# CONFIGURANDO OIDC (Auth0) #
#############################

vault auth enable oidc

vault write auth/oidc/config \
        oidc_discovery_url="https://$AUTH0_DOMAIN/" \
        oidc_client_id="$AUTH0_CLIENT_ID" \
        oidc_client_secret="$AUTH0_CLIENT_SECRET" \
        default_role="dev"

vault write auth/oidc/role/reader \
        bound_audiences="$AUTH0_CLIENT_ID" \
        allowed_redirect_uris="http://localhost:8200/ui/vault/auth/oidc/oidc/callback" \
        allowed_redirect_uris="http://localhost:8250/oidc/callback" \
        user_claim="sub" \
        policies="dev"

# Esse é o método de autenticação para desenvolvedores!
#  vault login -method=oidc role="dev"

################################
# CONFIGURANDO KUBERNETES AUTH #
################################

# Criando a ServiceAccount e ClusterRoleBinding
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-auth
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: role-tokenreview-binding
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: vault-auth
  namespace: default
EOF

# VAULT_SA_NAME: nome da ServiceAccount que acabamos de criar
export VAULT_SA_NAME=$(kubectl get sa vault-auth -o jsonpath="{.secrets[*]['name']}")

# SA_JWT_TOKEN: valor do JWT da ServiceAccount, usada para acessar a TokenReview API
export SA_JWT_TOKEN=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data.token}" | base64 --decode; echo)

# SA_CA_CRT: certificado usado para autenticar com a api do Kubernetes
export SA_CA_CRT=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data['ca\.crt']}" | base64 --decode; echo)

# K8S_HOST: ip do Minikube
export K8S_HOST=$(minikube ip)

# Habilitando a autenticação pelo Kubernetes
vault auth enable kubernetes

# Configurando como o Vault se comunicará com o Minikube
vault write auth/kubernetes/config \
        token_reviewer_jwt="$SA_JWT_TOKEN" \
        kubernetes_host="https://$K8S_HOST:8443" \
        kubernetes_ca_cert="$SA_CA_CRT"

# Criando uma rolei chamada 'app' para mapear a ServiceAccount do Kubernetes
# para a Vault Policy 'app' (que criamos no início deste script)
vault write auth/kubernetes/role/app \
        bound_service_account_names=vault-auth \
        bound_service_account_namespaces=default \
        policies=app \
        ttl=24h
