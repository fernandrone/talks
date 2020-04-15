#!/bin/bash

# 'Trap' avisa o processo que quando sofrer as seguintes interrupções
# INT / TERM / QUIT / HUP, ele deve invocar a função 'handle' com o
# parâmetro correspondente

trap "handle INT" INT	# 2
trap "handle KILL" KILL # 9 - NÃO FUNCIONA
trap "handle TERM" TERM # 15

handle() {
    echo "Trapped: $1"
    echo "Encerrando o processo graciosamente..."
    
    sleep 2
    
    echo "Processo encerrado"

    exit 0 # Importante!
}

echo "Iniciando o processo (PID $$)..."

sleep infinity & # Espera para sempre e cria um novo processo
wait             # Espera o novo processo
