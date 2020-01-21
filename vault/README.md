# Segurança de Banco de Dados com Vault

Talk sobre Credenciais Dinâmicas (Dynamic Secrets) com Hashicorp Vault.

💻 [Slides](https://docs.google.com/presentation/d/1otRH8TSHg3kZV4Nm8YKcBaRCtonYUapg45XQIDqgNb8/edit?usp=sharing)

## Requisitos

* [Docker](https://docs.docker.com/install/linux/docker-ce/debian/)
* [Minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/#install-minikube-via-direct-download) (testado com 1.17.1)
* [Kubectl 1.15+](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-on-linux) (testado com 1.6.2)
* Um [Hypervisor](https://kubernetes.io/docs/tasks/tools/install-minikube/#install-a-hypervisor) (testado com [KVM2](https://www.linux-kvm.org/page/Main_Page))
* [Helm](https://helm.sh/blog/helm-3-released/) (testado com 3.0.2)
* [Vault](https://www.vaultproject.io/downloads/) (testado com 1.3.1)
* [jq](https://stedolan.github.io/jq/download/)

## Configuracao Vault

Primeiro, clonar esse repositorio:

```console
git clone https://github.com/fbcbarbosa/talks/ --recurse-submodules
```

Inicializar o Minikube:

```console
minikube start --vm-driver kvm2 --kubernetes-version v1.17.1
```

Entao, instalar o Vault no Kubertes:

```console
helm install vault ./vault-helm --set server.dev.enabled=true
```

Agora, exponha o Vault externamente:

```console
kubectl expose svc vault --type=LoadBalancer --port=8200 --target-port=8200 --name=vault-server
```

Verifique que o servidor subiu com o comando abaixo:

```console
minikube service vault-server
```

## Configuracao MySQL

Crie um banco MySQL:

```console
$ helm repo add stable https://kubernetes-charts.storage.googleapis.com
"stable" has been added to your repositories
```

```console
$ helm install meu-banco stable/mysql --set mysqlRootPassword=root --set mysqlDatabase=meu-banco
NAME: meu-banco
LAST DEPLOYED: Sun Jan 19 20:19:37 2020
NAMESPACE: default
STATUS: deployed
REVISION: 1
NOTES:
MySQL can be accessed via port 3306 on the following DNS name from within your cluster:
meu-banco-mysql.default.svc.cluster.local
```

Agora, rode o script de configuracao abaixo:

```console
./setup-vault.sh
```

Para logar como usuário:

```console
VAULT_SA_NAME=$(kubectl get sa dev -o jsonpath="{.secrets[*]['name']}") && \
KUBE_TOKEN=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data.token}" | base64 --decode; echo) && \
curl -v -d '{"jwt": "'"$KUBE_TOKEN"'", "role": "dev"}' $VAULT_ADDR/v1/auth/kubernetes/login | jq
```

Capturar o campo `client_token`, então utilizar a linha de comando do Vault autenticar localmente:

```
$ vault login s.QXbs2zqwmceTWuoAYkIFnjF8
```

Requisitar credenciais para o banco de dados:

```
$ vault read database/creds/read
Key                Value
---                -----
lease_id           database/creds/read/FJtrcGpXaEcyvn3BTxQ3LtwR
lease_duration     1h
lease_renewable    true
password           A1a-NxeTnrQaoK1kKE8s
username           v-kubernetes-read-AJ8NJQDRwuxroz
```

A permissão CRUD deve falhar:

```
$ vault read database/creds/crud
Error reading database/creds/crud: Error making API request.

URL: GET http://192.168.39.208:30770/v1/database/creds/crud
Code: 403. Errors:

* 1 error occurred:
        * permission denied
```

Para se conectar no banco de dados:

```
$ kubectl port-forward svc/meu-banco-mysql 3306
$ mysql =h 127.0.0.1 -u <username> -p<pwd> -D <meu-banco>
```

Comandos de leitura devem funcionar, mas comandos de escrita, não:

```
SELECT * FROM table;  # OK
CREATE TABLE 'minhatabela';  # FAIL
```
