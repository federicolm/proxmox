#!/bin/bash

# TODO 
# nome script : 
# utilizzo : ./creazioneVmDaTemplate.sh <NomeVM> <IDDelTemplateDellaVM> <NomeDelTemplateDelleRisorseDellaVM> <NomeUtente> <PasswordUtente> <ChiaveSSH> <IndirizzoIPDellaVM> <Gateway>
# 1) nome della vm
# 2) ID del template della vm
# 3) nome del template delle risorse
# 4) nome utente
# 5) password utente
# 6) chiave ssh
# 7) indirizzo ip della vm
# 8) gateway

nomeVM=$1

nomeTemplateVM=$2

nomeTemplateRisorse=$3

username=$4

password=$5

ssh=$6

ipAddress=$7

gateway=$8

lastID=$(qm list | grep -vi 'vmid' | awk '{print $1}' | sort | tail -1)

nextID=$(( lastIdUsed + 1 ))




qm clone 9000 $nextID --name $nomeVM ;

qm set $nextID --ipconfig0 ip=$ipAddress,gw=$gateway --agent enabled=1 --sshkey $ssh ;

qm resize $nextID scsi0 10G ; # imposta il disco a 10GB

qm resize $nextID scsi0 i+10G ; # ingrandisce il disco di 10GB rispetto alla sua dimensione precedente

qm set $nextID --sshkey $ssh ;
qm set $nextID --ciuser="$username" --cipassword="$password" ; #Pare non funzionare bene !
# qm set $nextID --cicustom "user=local:snippets/123.yaml" ;

# la parte di clonazione della vm e relativi settaggi, vanno creati fuori da questo script,
# il concetto è che questo script crei esclusivamente i template "quando servirà" e per la clonazione dal template si dovrà creare
# un modo per avere già un elenco di template ed a quali sistemi operativi corrispondono
	
