#!/bin/bash

# Parametri in ingresso da fornire allo script : 
# $2 : nome del bridge da usare per la scheda di rete
# $3 : path della ISO da utilizzare per l'installazione

numid=$(pvesh get /cluster/nextid)

bridge=$2

iso=$3

node=$(cat /etc/hostname)

pvesh create /nodes/$node/storage/local/content \
     -filename vm-$numid-disk-0.qcow2 \
     -format qcow2 -size 200G -vmid $numid

pvesh create /nodes/$node/qemu \
      -vmid $numid \
	  -memory 6144 \
      -sockets 1 \
	  -cores 4 \
      -net0 e1000,bridge=$bridge \
      -scsi0=local:$numid/vm-$numid-disk-0.qcow2 \
      -ide0=local:iso/$iso,media=cdrom

