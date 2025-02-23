#!/bin/bash

# Variabili di input
# $1 : immagine cloudinit
# $2 : pool storage

# Utilizzo dello script
# ./creazioneTemplateDaImmaginiCloudInit.sh <path immagine cloudinit> <pool statorage>

if [ ! $1 == "" ] ; then
	echo "Percorso della immagine specificato"
	echo "Percorso : $1"
	immagine=$1
else
	echo "Percorso della immagine non specificato"
	exit 1
fi

if [ ! $2 == "" ] ; then
	echo "Pool di storage specificato"
	echo "Storage : $2"
	# lista devices di storage : pvesh ls storage | awk '{print $2}'
	readarray -d '' -t targets < <(pvesh ls storage | awk '{print $2}')
	echo "dimensione array : ${#targets[@]}"
	for str in ${targets[@]}; do
		echo "Elemento : $str"
	done
	
	echo "Elemento 1 : ${targets[0]}"
	echo "Elemento 2 : ${targets[1]}"
	echo "Elemento 3 : ${targets[2]}"
	echo "Elemento 4 : ${targets[3]}"
	storage=$2
else
	echo "Pool di storage non specificato"
	exit 1
fi

# Numero di nodi del cluster
pvesh get nodes --output-format json | jq '.| length'

# Nome del primo nodo visto dal cluster
pvesh get nodes --output-format json | jq -r '.[0].node'

# Dall'id offset in poi ci sono i template delle VM
offset=9000

lastID=$(qm list | grep -vi 'vmid' | awk '{print $1}' | sort -n | tail -1)

if [[ $lastID -le $offset ]] ; then
	nextID=$(( offset + 1 ))
elif [[ $lastID -gt $offset ]] ; then
	nextID=$(( lastID + 1 ))
fi

qm create $nextID --memory 1024 --cores 1 --net0 virtio,bridge=vmbr0 ;

qm importdisk $nextID $immagine local-lvm ;

qm set $nextID --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-$nextID-disk-0 ;

qm set $nextID --ide2 local-lvm:cloudinit ;

qm set $nextID --boot c --bootdisk scsi0 ;

qm set $nextID --serial0 socket --vga serial0 ; # è necessario altrimenti non funziona l'accesso alla vm visto che è pensata per girare sotto openstack

qm template $nextID ;

