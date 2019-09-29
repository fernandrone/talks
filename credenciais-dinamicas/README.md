# Credenciais Dinamicas com Vault

Talk sobre *Dyanamic Secrets* com Hashicorp Vault.

## Requisitos

* Docker
* Minikube
* Helm3

## Configuracao Vault

Primeiro, configurar um dominio no site auth0.com:

```console
export AUTH0_DOMAIN=
export AUTH0_CLIENT_ID=
export AUTH0_CLIENT_SECRET=
```

No campo *Allowed Callback URLs*:

```console
http://127.0.0.1:8200/ui/vault/auth/oidc/oidc/callback,
http://127.0.0.1:8250/oidc/callback,
http://localhost:8200/ui/vault/auth/oidc/oidc/callback,
http://localhost:8250/oidc/callback
```

Agora inicializar o Minikube:

```console
minikube start --vm-driver kvm2 --kubernetes-version v1.15.4
```

Entao, instalar o Vault no Kubertes:

```console
helm3 install vault ./vault-helm --set server.dev.enabled=true
```

Agora, exponha o Vault externamente:

```console
kubectl expose svc vault --type=LoadBalancer --port=8200 --target-port=8200 --name=vault-server
```

Verifique que o servidor subiu com o comando abaixo:

```console
$ minikube service vault-server
```

## Configuracao MySQL

Agora, rode o script de configuracao abaixo:

```console
./setup-vault.sh
```

```console
helm repo add stable https://kubernetes-charts.storage.googleapis.com
helm3 install meu-banco stable/mysql --set mysqlRootPassword=root
```

> CUIDADO ao passar como argumento para o Helm, seu password de administrador do banco (junto com todas outras configurações) será salvo como um Kubernetes Secret dentro do cluster. Rodar banco de dados em Kubernetes é um tema bastante polêmico mas se utilizar essa estratégia tenha certeza que o acesso aos seus Secrets é controlado e garanta que você tem *[Encryption at Rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/).* 
