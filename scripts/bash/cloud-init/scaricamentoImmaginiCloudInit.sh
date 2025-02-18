#!/bin/bash

# Utilizzo script : 
# ./scaricamentoImmaginiCloudInit.sh <url cloudinit image> <path download>
# oppure : 
# ./scaricamentoImmaginiCloudInit.sh <url cloudinit image>
# in questo caso il default path sarà /var/lib/vz/template/cloudinit
# Lo script non eseguirà nessun controllo di esattezza di URL e path download che dovranno essere
# gestiti da chi lo richiama

defaultPath=/var/lib/vz/template/cloudinit
url=""
path=""

echo "Url cloudinit image : $1" 
echo "Path download : $2"

numbersInputVariables=$#
echo "Numero variabili in input : $numbersInputVariables"

presenza_directory(){
	if [[ -d $path ]]; then
		echo "il seguente path è presente : $path"
	else
		mkdir -p $path
		result=$?
		if [[ $result == "0" ]]; then
			echo "Path creato"
		else
			echo "Il path non è stato possibile crearlo, interrompo l'esecuzione"
			exit 1
		fi
	fi
}

case $numbersInputVariables in
	1 ) echo "Hai inserito esclusivamente l'url dell'immagine da scaricare"
		url=$1
		path=$defaultPath
		echo "Vuoi scaricare il seguente file : $url"
		echo "ed inserirlo nel seguente path : $path"
		presenza_directory
		wget $url -P $path
	;;
	2 ) echo "Hai inserito sia l'url che il path di download dell'immagine da scaricare"
		url=$1
		path=$2
		echo "Vuoi scaricare il seguente file : $url"
		echo "ed inserirlo nel seguente path : $path"
		presenza_directory
		wget $url -P $path
	;;
	* ) echo "hai inserito un numero sbagliato di parametri !"
		exit 1
	;;
esac
