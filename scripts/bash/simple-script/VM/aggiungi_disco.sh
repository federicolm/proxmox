#!/bin/bash

# Parametri in ingresso da fornire allo script : 
# $1 : id della VM
# $2 : nome dello storage
# $3 : dimensioni del disco da aggiungere
# $4 : 

numid=$1

name_storage=$2

size_disk=$3

nextId=$(grep disk /etc/pve/qemu-server/$numid.conf | wc -l)

pvesm alloc $name_storage $numid '' $size_disk --format qcow2

qm set $numid --scsihw virtio-scsi-pci --scsi$nextId $name_storage:$numid/vm-$numid-disk-$nextId.qcow2

