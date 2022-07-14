#!/bin/bash

# operazioni logiche da fare : 
# 
# 1) spegnere la vm
# 2) saputo quale sia il disco da ingrandire (per semplicità sarà una variabile in ingresso) oppure si presuppone che la vm abbia un solo disco.
# 3) TODO
# Parametri in ingresso
# $1 : id della vm
# $2 : incremento di dimensione
# da identificare il disco interno della vm

numid=$1

grow_size=$2

disk=$(pvesm list pool-raid6 -vmid 100 | cut -d " " -f 1 | sed 1d)



qm resize $numid $disk $grow_size
