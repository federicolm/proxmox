#!/bin/bash
#
# Script di migrazione vm tra nodi di un cluster
#
# Utilizzo : ./migrazione_vm.sh <vmid> <nodo destinazione> <>
#
# Opzioni interne da valutare del comando "qm migrate"
#
# --migration_network <string>
# CIDR of the (sub) network that is used for migration.
#
# --migration_type <insecure | secure>
# Migration traffic is encrypted using an SSH tunnel by default. On secure, completely private networks this can be disabled to increase performance.
#
# --online <boolean>
# Use online/live migration if VM is running. Ignored if VM is stopped.
#
# --targetstorage <string>
# Mapping from source to target storages. Providing only a single storage ID maps all source storages to that storage. Providing the special value 1 will map each source storage to itself.
#
# --with-local-disks <boolean>
# Enable live storage migration for local disk
#
# Valutare la tipologia di storage su cui risiede la vm per differenziale le casistiche di storale locale e storage distribuito o remoto, in modo tale
# da utilizzare o meno l'opzione --with-local-disks <boolean>

vmid=$1
destination=$2

echo "id vm : $vmid"
echo "destionazione : $destination"

qm migrate $vmid $destination --online
result=$?

if [[ $rsult == "0" ]];then
	echo "Migrazione avvenuta correttamente"
else
	echo "Si è verificato un errore di migrazione"
fi
