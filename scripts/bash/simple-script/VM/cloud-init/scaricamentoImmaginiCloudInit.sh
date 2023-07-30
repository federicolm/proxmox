#!/bin/bash

# Utilizzo script : 
# se si vuole usare un path personalizzato
# ./scaricamentoImmaginiCloudInit.sh <url cloudinit image> <path download>
# se si vuole usare il path di default 
# ./scaricamentoImmaginiCloudInit.sh <url cloudinit image> 
# Lista variabili input
# $1 : url del file cloudinit da scaricare
# $2 : path dove scaricare il file di cloudinit

defaultPath=/var/lib/vz/template/cloudinit

echo "\$1 : $1" 
echo "\$2 : $2"

if [ ! $1 == "" ] ; then
	echo "Percorso immagine specificato ed esistente"
	defaultPath=$2
else
	echo "Percorso della immagine non specificato"
	exit 1
fi


if [ $2 != "" ] ; then
	echo "Percorso impostato ed esistente"
	defaultPath=$2
else
	echo "Percorso non specificato si utilizza quello di default"
fi

if [[ ! -d $defaultPath ]] ; then
	mkdir -p $defaultPath
	echo "Il percorso di default non esiste ed è stata creata"
else
	echo "La directory esiste !"
fi

url=$1

destinazione=$2


my_arr=($(echo $url | tr "/" "\n"))
echo "my_arr : $my_arr"
nomeFile=${my_arr[-1]}
echo "$nomeFile"

if [[ ! -f $defaultPath/$nomeFile ]]; then
	echo "il file non esiste !"
	ls -la $defaultPath/$nomeFile
	wget -P $defaultPath $url
	/usr/bin/ls $defaultPath/$nomeFile
	retVal=$?
	echo "#############################"
	echo "stato di uscita del wget : $retVal"
	echo "#############################"
	echo "Scaricato il file $nomeFile in $defaultPath"
	ls -la $defaultPath/$nomeFile
else
	echo "Il file $defaultPath/$nomeFile esiste"
fi
