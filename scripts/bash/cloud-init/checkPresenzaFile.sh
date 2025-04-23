#!/bin/bash
#
# Lo scopo di questo script è verificare la presenza, in un determinato path
# all'interno di un nodo proxmox oppure di un pool di storage condiviso in un cluster
# oppure in uno storage remoto, di un determinato file che può essere o un'immagine cloud-init o un file iso di installazione di un OS
# passato come URL in ingresso e relativo hash md5/sha256
#
# Parametri di input : 
# $1 : pool di storage
# $2 : hash del file md5/sha
# $3 : URL dell'immagine qcow2/iso da verificare o da scaricare
# $4 : nome del file
#
# Esempio di file iso/qcow2 da verificarne la presenza : 
# nome del file : Rocky-9-GenericCloud-Base-9.5-20241118.0.x86_64.qcow2
# url : https://rockylinux.mirror.garr.it/9.5/images/x86_64/Rocky-9-GenericCloud-Base-9.5-20241118.0.x86_64.qcow2
# sha256 : 069493fdc807300a22176540e9171fcff2227a92b40a7985a0c1c9e21aeebf57
# pool qcow2 : /var/lib/vz/template/cloudinit/
# pool iso : /var/lib/vz/template/iso/
#
# Utilizzo dello script : ./checkPresenzaFile.sh <pool di storage> <algoritmo di hash> <hash del file> <url del file> <nome del file>
# 
# Versione : 0.0.1
# Data : 17/04/2025
# Autore : Federico La Morgia <federico.lamorgia@gmail.com>
#


echo "stampa parametri di input"
echo $1
echo $2
echo $3
echo $4
echo $5





# Dichiarazione delle variabili
readonly poolStorage=$1
readonly algoritmoHash=$2
readonly hashFile=$3
readonly urlFile=$4
readonly nomeFile=$5

# Controlli preliminari
# 1. Verificare che tutti i necessari parametri di input siano stati inseriti
# 2. Verificare la correttezza di tutti i parametri di input inseriti
# 3. Nel caso il file dell'URL non sia presente nello storage indicato, 
#    verificare se c'è lo spazio necessario per la sua memorizzazione


# 1. Verifica presenza parametri in ingresso
if [ -z "${poolStorage}" ] ; then
	echo "Non si è inserito il poolStorage"
	exit -1
fi

if [ -z "${algoritmoHash}" ] ; then
	echo "Non si è inserito l'algoritmo di hash del file"
	exit -1
fi

if [ -z "${hashFile}" ] ; then
	echo "Non si è inserito l'hash del file"
	exit -1
fi

if [ -z "${nomeFile}" ] ; then
	echo "Non si è inserito il nome del file"
	exit -1
fi


echo "pool di storage : $poolStorage"
echo "algoritmo di hash : $algoritmoHash"
echo "hash del file : $hashFile"
echo "Nome del file da verificare : $nomeFile"
echo "url del file : $urlFile"


# 2. Verifica correttezza parametri in ingresso

echo $urlFile | grep -Eq '^http://'
risultato_http=$?

echo $urlFile | grep -Eq '^https://'
risultato_https=$?

echo $urlFile | grep  -Eq '\.iso$'
risultato_iso=$?

echo $urlFile | grep -Eq '\.qcow2$'
risultato_qcow2=$?

if [[ $risultato_iso == 0  ]] ; then
	echo "l'url riguarda un file .iso"
	echo "url inserita : $urlFile"
fi

if [[ $risultato_qcow2 == 0 ]] ; then
	echo "l'url riguarda un file .qcow2"
	echo "url inserita : $urlFile"
fi



