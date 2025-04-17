#!/bin/bash
#
# Lo scopo di questo script è verificare la presenza, in un determinato path
# all'interno di un nodo proxmox oppure di un pool di storage condiviso in un cluster
# oppure in uno storage remoto, di un determinato file passato come URL in ingresso e relativo hash md5/sha
#
# Parametri di input : 
# $1 : pool di storage
# $2 : hash del file md5/sha
# $3 : URL dell'immagine qcow2/iso da verificare o da scaricare
#
# Utilizzo dello script : ./checkPresenzaFile.sh <pool di storage> <hash del file> <url del file> 
# 
# Versione : 0.0.1
# Data : 17/04/2025
# Autore : Federico La Morgia <federico.lamorgia@gmail.com>
#

pool=$1
hash=$2
url=$3

echo "Parametro 1 : $pool"
echo "Parametro 2 : $hash"
echo "Parametro 3 : $url"
