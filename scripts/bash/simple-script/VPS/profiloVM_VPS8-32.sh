#!/bin/bash

# Parametri in ingresso da fornire allo script : 
# $1 : nome della vm
# $2 : nome del bridge da usare per la scheda di rete
# $3 : path della ISO da utilizzare per l'installazione
# $4 : nome del pool di storage da utilizzare compatibile con il formato qcow2

numid=$(pvesh get /cluster/nextid)

name_vm=$1

bridge=$2

iso=$3

name_storage=$4

node=$(cat /etc/hostname)

pvesh create /nodes/$node/storage/$name_storage/content \
     -filename vm-$numid-disk-0.qcow2 \
     -format qcow2 -size 500G -vmid $numid

pvesh create /nodes/$node/qemu \
	-name $name_vm \
	-vmid $numid \
	-memory 32768 \
	-sockets 1 \
	-cores 8 \
	-net0 e1000,bridge=$bridge \
	-scsi0=$name_storage:$numid/vm-$numid-disk-0.qcow2 \
	-ide0=local:iso/$iso,media=cdrom
