# Projetando Containers Descartáveis

_Como tratar sinais no Docker e Kubernetes!_

- 💻 [Slides](https://fdr.one/sinais-slides)

## Requisitos

- [Docker](https://docs.docker.com/install/linux/docker-ce/debian/)
- [Minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/#install-minikube-via-direct-download) (testado com 1.9.2)
  - Um [Hypervisor](https://kubernetes.io/docs/tasks/tools/install-minikube/#install-a-hypervisor) (testado com [KVM2](https://www.linux-kvm.org/page/Main_Page))
- [Kubectl 1.17+](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-on-linux) (testado com 1.18.1)

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

Crie uma imagem a partir do Dockerfile `Dockerfile.exec`.

```console
$ docker build -t trap:exec -f Dockerfile.exec .
Sending build context to Docker daemon   7.68kB
Step 1/3 : FROM debian:stable
 ---> 5e3221e89de8
Step 2/3 : ADD trap.sh trap.sh
 ---> Using cache
 ---> 96dbeb823e76
Step 3/3 : ENTRYPOINT [ "./trap.sh" ]
 ---> Running in 208b5f6ce010
Removing intermediate container 208b5f6ce010
 ---> 995514e0f23b
Successfully built 995514e0f23b
Successfully tagged trap:exec
```

Agora inicie um container a partir desse imagem:

```console
$ docker run -it --rm --name trap trap:exec
Iniciando o processo (PID 1)...
```

Você perceberá que o processo se iniciou com o ID 1. Em um novo terminal, pare o container:

```console
$ docker stop trap
```

Você vera o sinal TERM ser capurado:

```console
Trapped: TERM
Encerrando o processo graciosamente...
Processo encerrado
```

Repita o processo com a imagem Dockerfile.shell.

```console
$ docker build -t trap:shell -f Dockerfile.shell .
Sending build context to Docker daemon  6.656kB
Step 1/3 : FROM debian:stable
 ---> 5e3221e89de8
Step 2/3 : ADD trap.sh trap.sh
 ---> Using cache
 ---> 96dbeb823e76
Step 3/3 : ENTRYPOINT "./trap.sh"
 ---> Running in e55f122d4c92
Removing intermediate container e55f122d4c92
 ---> fb6d971ed0f9
Successfully built fb6d971ed0f9
Successfully tagged trap:shell
```

Agora inicie um container a partir da nova imagem:

```console
$ docker run -it --rm --name trap trap:shell
Iniciando o processo (PID 7)...
```

Dessa vez processo se iniciou com um ID diferente de 1 (no meu exemplo, foi o ID 7, mas poderia ser outro qualquer)! Novamente, em um outro terminal, para container:

```console
$ docker stop trap
```

Dessa vez o sinal **não** será capturado! Além disso levará 10 segundos para o container finalizar, e o processo retornará um _status code_ 137, indicando que terminou com erro.

**O que aconteceu?**

Quando usamos a forma o Dockerfile com o Entrypoint na forma _shell_, o processo não recebe os sinais do sistema. Assim ele não recebe o SIGTERM do docker stop, sendo apenas terminado com um SIGKILL após o timeout. Veja a [documentação](https://docs.docker.com/engine/reference/builder/#entrypoint) do entrypoint.

> ENTRYPOINT has two forms:
>
> ENTRYPOINT ["executable", "param1", "param2"] (exec form, preferred)
> ENTRYPOINT command param1 param2 (shell form)
> An ENTRYPOINT allows you to configure a container that will run as an executable.
>
> For example, the following will start nginx with its default content, listening on port 80:
>
> docker run -i -t --rm -p 80:80 nginx
> Command line arguments to docker run <image> will be appended after all elements in an exec form ENTRYPOINT, and will override all elements specified using CMD. This allows arguments to be passed to the entry point, i.e., docker run <image> -d will pass the -d argument to the entry point. You can override the ENTRYPOINT instruction using the docker run --entrypoint flag.
>
> The shell form prevents any CMD or run command line arguments from being used, but has the disadvantage that your ENTRYPOINT will be started as a >subcommand of /bin/sh -c, which does not pass signals. This means that the executable will not be the container’s PID 1 - and will not receive Unix >signals - so your executable will not receive a SIGTERM from docker stop <container>.

## Kubernetes

Inicializar o Minikube:

```console
minikube start --vm-driver kvm2 --kubernetes-version v1.17.1
```

Configure o Minikube para usar o docker daemon local:

```console
eval $(minikube docker-env)
```

Crie um pod a partir do arquivo `pod-exec.yml`. Em um terminal distinto, verifique seus logs:

```console
$ kubectl apply -f pod-exec.yml
$ kubectl logs -f trap-exec
Iniciando o processo (PID 1)...
```

O _pod_ está usando a imagem _trap:exec_, que inicializa como PID 1, permitindo a captura dos sinais do sistema corretamente. 

> 🛈 Nossos manifestos não definem o campo _command_, comumente utilizado para sobrescrever o _entrypoint_ da imagem Docker de cada container presente no _Pod_. Isso faz com que o Pod inicie utilizando o _entrypoint_ definido na imagem do container.

Utilize `kubectl delete` e verifique que o comando é terminado imediatamente, significando que o sinal TERM é capturado.

```console
$ kubectl delete pod pod-exec
```

Na janela dos logs, você deve visualizar a seguinte mensagem:

```console
Iniciando o processo (PID 1)...
Trapped: TERM
Encerrando o processo graciosamente...
Processo encerrado
```

Crie agora um novo pod a partir do arquivo `pod-shell.yml`.

```console
$ kubectl apply -f pod-shell.yml
$ kubectl logs -f trap-shell
Iniciando o processo (PID 6)...
```

Este está utilizando a imagem _trap:shell_ e, quando removido, não fará a captura do sinal.

```console
$ kubectl delete pod pod-shell
```

Note que o comando ficará "preso" por 10 segundos, o valor do `terminationGracePeriodSeconds` que configuramos para o _pod_, e finalizará sem imprimir a mensagem de  encerramento gracioso.

Você pode também modificar as configurações `preStop` e `terminationGracePeriodSeconds` para averiguar o funcionamento delas.

## Extras

As mensagens abaixo mostram os outputs dos logs do Docker Daemon quando o comando `docker stop` é invocado na imagem `docker stop`. É possível visualizar a tentativa de parar o container graciosamente utilizando-se a API `/stop` com o sinal 15 (SIGTERM). Após 10 segundos, a API `/delete` é invocada, que envia o sinal 9 (SIGKILL).

```console
$ docker run -it trap:shell # id e9c6e729c0dc
$ docker stop e9c6e729c0dc
...
$ journalctl -u docker.service -f
nov 08 19:48:28 A40 dockerd[1788]: time="2020-11-08T19:48:28.153599523-03:00" level=debug msg="Calling POST /v1.40/containers/e9c6e729c0dc/stop"
nov 08 19:48:28 A40 dockerd[1788]: time="2020-11-08T19:48:28.153690763-03:00" level=debug msg="Sending kill signal 15 to container e9c6e729c0dc819e2fd098677c608573ba9c9bf4c113f7f22c2c1e832b39d7f1"
nov 08 19:48:38 A40 dockerd[1788]: time="2020-11-08T19:48:38.187468949-03:00" level=info msg="Container e9c6e729c0dc819e2fd098677c608573ba9c9bf4c113f7f22c2c1e832b39d7f1 failed to exit within 10 seconds of signal 15 - using the force"
nov 08 19:48:38 A40 dockerd[1788]: time="2020-11-08T19:48:38.187534771-03:00" level=debug msg="Sending kill signal 9 to container e9c6e729c0dc819e2fd098677c608573ba9c9bf4c113f7f22c2c1e832b39d7f1"
nov 08 19:48:38 A40 dockerd[1788]: time="2020-11-08T19:48:38.281850454-03:00" level=debug msg=event module=libcontainerd namespace=moby topic=/tasks/exit
nov 08 19:48:38 A40 dockerd[1788]: time="2020-11-08T19:48:38.310744602-03:00" level=debug msg=event module=libcontainerd namespace=moby topic=/tasks/delete
nov 08 19:48:38 A40 dockerd[1788]: time="2020-11-08T19:48:38.310815213-03:00" level=info msg="ignoring event" module=libcontainerd namespace=moby topic=/tasks/delete type="*events.TaskDelete"
nov 08 19:48:38 A40 dockerd[1788]: time="2020-11-08T19:48:38.310763858-03:00" level=debug msg="attach: stdout: end"
nov 08 19:48:38 A40 dockerd[1788]: time="2020-11-08T19:48:38.310767074-03:00" level=debug msg="attach: stderr: end"
nov 08 19:48:38 A40 dockerd[1788]: time="2020-11-08T19:48:38.310773776-03:00" level=debug msg="attach: stdin: end"
nov 08 19:48:38 A40 dockerd[1788]: time="2020-11-08T19:48:38.310969770-03:00" level=debug msg="attach done"
nov 08 19:48:38 A40 dockerd[1788]: time="2020-11-08T19:48:38.311130177-03:00" level=debug msg="Closing buffered stdin pipe"
nov 08 19:48:38 A40 dockerd[1788]: time="2020-11-08T19:48:38.311363550-03:00" level=debug msg="Revoking external connectivity on endpoint priceless_villani (9a60a4b15cec575c559c33c8b004e60632bb41a64c0fe1476cef855393749272)"
nov 08 19:48:38 A40 dockerd[1788]: time="2020-11-08T19:48:38.313481519-03:00" level=debug msg="DeleteConntrackEntries purged ipv4:0, ipv6:0"
nov 08 19:48:38 A40 dockerd[1788]: time="2020-11-08T19:48:38.465232694-03:00" level=debug msg="Releasing addresses for endpoint priceless_villani's interface on network bridge"
nov 08 19:48:38 A40 dockerd[1788]: time="2020-11-08T19:48:38.465297504-03:00" level=debug msg="ReleaseAddress(LocalDefault/172.17.0.0/16, 172.17.0.2)"
nov 08 19:48:38 A40 dockerd[1788]: time="2020-11-08T19:48:38.465355402-03:00" level=debug msg="Released address PoolID:LocalDefault/172.17.0.0/16, Address:172.17.0.2 Sequence:App: ipam/default/data, ID: LocalDefault/172.17.0.0/16, DBIndex: 0x0, Bits: 65536, Unselected: 65532, Sequence: (0xe0000000, 1)->(0x0, 2046)->(0x1, 1)->end Curr:3"
```
