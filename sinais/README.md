# Projetando Containers Descartáveis

_Como tratar sinais no Docker e Kubernetes!_

## Requisitos

- [Docker](https://docs.docker.com/install/linux/docker-ce/debian/)
- [Minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/#install-minikube-via-direct-download) (testado com 1.9.2)
  - Um [Hypervisor](https://kubernetes.io/docs/tasks/tools/install-minikube/#install-a-hypervisor) (testado com [KVM2](https://www.linux-kvm.org/page/Main_Page))
- [Kubectl 1.17+](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-on-linux) (testado com 1.18.1)
- [jq](https://stedolan.github.io/jq/download/)

## Sinais

Execute o programa `trap.sh`. Veja como ele trata (_handle_) os diferentes sinais do sistema operacional.

```console
$ ./trap.sh
Iniciando o processo (PID 28374)...
```

Abra outro terminal e execute `kill $PID` para enviar o sinal SIGTERM para o programa.

```console
$ kill 28374
```

Você deve ver o programa `trap.sh` exibindo a mensagem abaixo:

```console
Iniciando o processo (PID 28374)...
Trapped: TERM
Encerrando o processo graciosamente...
Processo encerrado
```

## Docker

## Configuração

Primeiro, clonar esse repositório:

```console
git clone https://github.com/fbcbarbosa/talks/ --recurse-submodules
```

Inicializar o Minikube:

```console
minikube start --vm-driver kvm2 --kubernetes-version v1.17.1
```

Configure o Minikube para usar o docker daemon local:

```
eval $(minikube docker-env)
```
