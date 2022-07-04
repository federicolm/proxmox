#!/bin/bash

# Parametri in ingresso da fornire allo script : 
# $1 : nome della vm
# $2 : nome del bridge da usare per la scheda di rete
# $3 : path della ISO da utilizzare per l'installazione
# $4 : dimensione della memoria ram in KB
# $5 : numero dei cores assegnati alla VM
# $6 : numero dei sockets assegnati alla VM
# $7 : nome dello storage dove memorizzare i files della vm
# $8 : dimensione del disco da creare in GB


numid=$(pvesh get /cluster/nextid)

name_vm=$1

bridge=$2

iso=$3

vmem=$4

vcpu=$5

vsockets=$6

name_storage=$7

size_disk=$8

node=$(cat /etc/hostname)


echo "Elenco variabili in ingresso"
echo "numid : $numid"
echo "bridge : $bridge"
echo "iso : $iso"
echo "vmem : $vmem"
echo "vcpu : $vcpu"
echo "vsockets : $vsockets"
echo "name_storage : $name_storage"
echo "size_disk : $size_disk"
echo "node : $node"


echo "creazione disco"
pvesh create /nodes/$node/storage/$name_storage/content \
     -filename vm-$numid-disk-0.qcow2 \
     -format qcow2 -size $size_disk -vmid $numid

echo "creazione vm"
pvesh create /nodes/$node/qemu \
	-vmid $numid \
	-memory $vmem \
	-sockets $vsockets \
	-cores $vcpu \
	-net0 e1000,bridge=$bridge \
	-scsi0=$name_storage:$numid/vm-$numid-disk-0.qcow2 \
	-ide0=local:iso/$iso,media=cdrom

