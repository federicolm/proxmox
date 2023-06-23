#!/bin/bash

# Lista variabili input
# $1 : url del file cloudinit da scaricare
# $2 : path dove scaricare il file di cloudinit

defaultPath=/var/lib/vz/template/cloudinit

if [[ ! -d $defaultPath ]] ; then
	mkdir -p $defaultPath
	echo "La directory non esiste ed è stata creata"
else
	echo "La directory esiste !"
fi

url=$1

destinazione=$2

#sizeList=${#listDownload[@]}

echo "dimensione array : ${#targets[@]}"

my_arr=($(echo $url | tr "/" "\n"))
echo "my_arr : $my_arr"
nomeFile=${my_arr[-1]}
echo "$nomeFile"
#if [[ ! -f $defaultPath/$nomeFile ]]; then
#	echo "il file non esiste !"
#	ls -la $defaultPath/$nomeFile
#	wget -P $defaultPath $str
#	/usr/bin/ls $defaultPath/$nomeFile
#	retVal=$?
#	echo "#############################"
#	echo "stato di uscita del wget : $retVal"
#	echo "#############################"
#	echo "Scaricato il file $nomeFile in $defaultPath"
#	ls -la $defaultPath/$nomeFile
#else
#	echo "Il file $defaultPath/$nomeFile esiste"
#fi