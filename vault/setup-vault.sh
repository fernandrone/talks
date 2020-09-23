#!/bin/bash
set -euf -o pipefail

# valor padrão em dev mode no Helm Chart
export VAULT_TOKEN=root 

#####################################
# CONFIGURANDO MYSQL SECRETs ENGINE #
#####################################

vault secrets enable database

vault write database/config/meu-banco \
    allowed_roles="*" \
    plugin_name=mysql-database-plugin \
    connection_url="{{username}}:{{password}}@tcp(meu-banco-mysql:3306)/" \
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
path "/database/creds/read" {
    capabilities = ["read", "list"]
}
EOF

# APP policy: acesso a ROLE 'crud'
cat <<EOF | vault policy write app - 
path "/database/creds/crud" {
    capabilities = ["read", "list"]
}
EOF

################################
# CONFIGURANDO KUBERNETES AUTH #
################################

# Habilitando a autenticação pelo Kubernetes
vault auth enable kubernetes

cat <<EOF | kubectl apply -f -
---
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

# K8S_HOST: ip do Minikube
export K8S_HOST=$(minikube ip)

# VAULT_SA_NAME: nome da ServiceAccount que acabamos de criar
export VAULT_SA_NAME=$(kubectl get sa vault-auth -o jsonpath="{.secrets[*]['name']}")

# SA_JWT_TOKEN: valor do JWT da ServiceAccount, usada para acessar a TokenReview API
export SA_JWT_TOKEN=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data.token}" | base64 --decode; echo)

# SA_CA_CRT: certificado usado para autenticar com a api do Kubernetes
export SA_CA_CRT=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data['ca\.crt']}" | base64 --decode; echo)

# Configurando como o Vault se comunicará com o Minikube
vault write auth/kubernetes/config \
        token_reviewer_jwt="$SA_JWT_TOKEN" \
        kubernetes_host="https://$K8S_HOST:8443" \
        kubernetes_ca_cert="$SA_CA_CRT"

###################################################################
# CONFIGURANDO AS SERVICE ACCOUNTS DE USUARIO/APLICACAO (DEV/APP) #
###################################################################

# Criando as ServiceAccounts e as ClusterRoleBindings
# uma para a aplicação 'app' e outra para a pessoa desenvolvedora 'dev'
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app
  namespace: default

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: role-app-binding
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: app
  namespace: default

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dev
  namespace: default

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: role-dev-binding
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: dev
  namespace: default
EOF

export APP_VAULT_SA_NAME=$(kubectl get sa app -o jsonpath="{.secrets[*]['name']}")
export APP_SA_CA_CRT=$(kubectl get secret $APP_VAULT_SA_NAME -o jsonpath="{.data['ca\.crt']}" | base64 --decode; echo)
export APP_SA_JWT_TOKEN=$(kubectl get secret $APP_VAULT_SA_NAME -o jsonpath="{.data.token}" | base64 --decode; echo)

export DEV_VAULT_SA_NAME=$(kubectl get sa dev -o jsonpath="{.secrets[*]['name']}")
export DEV_SA_JWT_TOKEN=$(kubectl get secret $DEV_VAULT_SA_NAME -o jsonpath="{.data.token}" | base64 --decode; echo)
export DEV_SA_CA_CRT=$(kubectl get secret $DEV_VAULT_SA_NAME -o jsonpath="{.data['ca\.crt']}" | base64 --decode; echo)

# Criando uma role chamada 'app' para mapear a ServiceAccount do Kubernetes
# para a Vault Policy 'app', com permissão de escrita no banco de dados
vault write auth/kubernetes/role/app \
        bound_service_account_names=app \
        bound_service_account_namespaces=default \
        policies=app \
        ttl=24h

# Criando uma role chamada 'dev' para mapear a ServiceAccount do Kubernetes
# para a Vault Policy 'dev', com permissão de leitura apenas do banco de dados
vault write auth/kubernetes/role/dev \
        bound_service_account_names=dev \
        bound_service_account_namespaces=default \
        policies=dev \
        ttl=24h
