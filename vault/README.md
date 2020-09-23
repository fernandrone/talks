# Segurança de Banco de Dados com Vault

Talk sobre Credenciais Dinâmicas (Dynamic Secrets) com Hashicorp Vault.

💻 [Slides](https://speakerdeck.com/fernandrone/seguranca-de-banco-de-dados-com-vault)

## Requisitos

- [Docker](https://docs.docker.com/install/linux/docker-ce/debian/) (testado com 19.03.12)
- [Minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/#install-minikube-via-direct-download) (testado com Minikube 1.13.1 / Kubernetes 1.19.2)
  - Um [Hypervisor](https://kubernetes.io/docs/tasks/tools/install-minikube/#install-a-hypervisor) (testado com [KVM2](https://minikube.sigs.k8s.io/docs/drivers/kvm2/))
- [Kubectl 1.17+](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-on-linux) (testado com 1.19.2)
- [Helm 3.0+](https://helm.sh/docs/intro/install/) (testado com 3.3.4)
- [Vault 1.0+](https://www.vaultproject.io/downloads/) (testado com 1.5.3)
- [jq](https://stedolan.github.io/jq/download/ (testado com 1.6.1)
- [mysql-client](https://dev.mysql.com/doc/mysql-installation-excerpt/8.0/en/) (testado com 8.0.21)

## Configuração Vault

Primeiro, clonar esse repositório:

```console
git clone https://github.com/fbcbarbosa/talks/ --recurse-submodules
```

> 🛈 se você já fez o clone, você pode inicializar os submódulos com o comando abaixo:

    ```console
    git submodule update --init --recursive
    ``` 

Inicializar o Minikube:

```console
minikube start --vm-driver kvm2
```

Então, instalar o Vault no Kubernetes:

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

Configure a varíavel VAULT_ADDR com o endereço do vault:

```console
export VAULT_ADDR=$(minikube service vault-server --url)
```

Agora vamos logar como um usuário. Para isso, adquirimos o token da _Service Account_ **dev** do Kubernetes. Esse _token_ está encodado no formato base64, por isso é necessário decodá-lo. Na sequência, fazemos uma chamada de API para o servidor do Vault utilizando esse _token_ e informando que desejamos fazer login com a _role_ de usuário **dev**.

> 🛈 tanto as _Service Accounts_ quando as _roles_ foram configuradas pelo script [setup_vault.sh](./setup_vault.sh).

```console
VAULT_SA_NAME=$(kubectl get sa dev -o jsonpath="{.secrets[*]['name']}") && \
  KUBE_TOKEN=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data.token}" | base64 --decode; echo) && \
  curl -sd '{"jwt": "'"$KUBE_TOKEN"'", "role": "dev"}' $VAULT_ADDR/v1/auth/kubernetes/login | jq
```

Capturar o campo `client_token`, então utilizar a linha de comando do Vault autenticar localmente:

```console
$ vault login <client-token>
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

...
```

Tente adquirir a permissão `crud`. Essa operação deve *falhar*, pois nos conectamos com a _role_ **dev**, de usuário. Essa permissão só nos dá acesso de leitura, conforme foi configurado no script [setup_vault.sh](./setup_vault.sh).

```
$ vault read database/creds/crud
Error reading database/creds/crud: Error making API request.

URL: GET http://192.168.39.208:30770/v1/database/creds/crud
Code: 403. Errors:

* 1 error occurred:
        * permission denied
```

Agora tente adquirir a permissão `read`. Essa operação deve completar com sucesso!

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

> 🛈 perceba que obtemos uma credencial **dinâmica**, temporária, com 1h de duração, ou _lease_; após esse tempo a credencial se tornará inválida!

Para se conectar no banco de dados, vamos fazer um _port-forward_ com o _pod_ do MySQL:

```
$ kubectl port-forward svc/meu-banco-mysql 3306 &
$ mysql -h 127.0.0.1 -D meu-banco -u <user> -p<pwd> 
```

Comandos de escrita devem falhar:

```mysql
$ mysql> CREATE TABLE tbl(
   id INT NOT NULL AUTO_INCREMENT,
   nome VARCHAR(100) NOT NULL,
   sobrenome VARCHAR(100) NOT NULL,
   PRIMARY KEY ( id )
);
ERROR 1142 (42000): CREATE command denied to user ...
```

Porém comandos de leitura devem funcionar. Troque para a database `mysql` e leia o conteúdo da tabela user:

```mysql
$ mysql> USE mysql;
$ mysql> SELECT user FROM user;
```

Podemos repetir os passos, agora com o token da aplicação, que tem permissão de escrita.

```console
$ VAULT_SA_NAME=$(kubectl get sa app -o jsonpath="{.secrets[*]['name']}") && \
  KUBE_TOKEN=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data.token}" | base64 --decode; echo) && \
  curl -sd '{"jwt": "'"$KUBE_TOKEN"'", "role": "app"}' $VAULT_ADDR/v1/auth/kubernetes/login | jq
...
$ vault login <client-token>
...
```

Agora o comandos de escrita no banco devem funcionar:

```
$ mysql -h 127.0.0.1 -D meu-banco -u <user> -p<pwd> 
$ mysql> CREATE TABLE tbl(
   id INT NOT NULL AUTO_INCREMENT,
   nome VARCHAR(100) NOT NULL,
   sobrenome VARCHAR(100) NOT NULL,
   PRIMARY KEY ( id )
);
```

Verificamos então que o sitema de **autorização** e **autenticaçao** do Vault funciona corretamente!

***

Vamos tentar revogar a credencial. Note que é necessário se conectar como usuário _root_, do contrário não temos permissão de revogar _leases_.

```console
$ VAULT_TOKEN=root vault lease revoke database/creds/read/...
```

Ao tentar se conectar ao banco de dados novamente, devemos ter a requisição negada:

```console
$ mysql -h 127.0.0.1 -D meu-banco -u <user> -p<pass>
mysql: [Warning] Using a password on the command line interface can be insecure.
ERROR 1045 (28000): Access denied for user ...
```

***

E é isso! Você pode agora pausar o cluster com o comando abaixo:

```console
$ minikube stop
```

Ou, caso deseje remover a configuração atual do cluster (incluindo os _pods_ do Vault, MySQL, Helm, etc.): 

```console
$ minikube delete
```