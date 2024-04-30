#!/bin/bash

# Utilizzo script : 
# se si vuole usare un path personalizzato
# ./scaricamentoImmaginiCloudInit.sh <url cloudinit image> <path download>
# se si vuole usare il path di default 
# ./scaricamentoImmaginiCloudInit.sh <url cloudinit image> 
# Lista variabili input
# $1 : url del file cloudinit da scaricare
# $2 : path dove scaricare il file di cloudinit

checkURL(){
	regex="http?(s)"
	if [[ "$url" == ${regex}* ]] ; then
		echo "l'url fa matching con http/s"
	else
		echo "l'url non fa matching con http/s"
		exit 1
	fi
}

checkPathDownload(){
	ls -la $defaultPath
	ritorno=$?
	if [ $ritorno == "0" ] ; then
		echo "Il path di download immesso risulta essere corretto"
	else
		echo "Il path di download non esiste, mi interrompo"
		exit 1
	fi
}

defaultPath=/var/lib/vz/template/cloudinit
url=""

echo "Url cloudinit image : $1" 
echo "Path download : $2"

numbersInputVariables=$#
echo "Numero variabili in input : $numbersInputVariables"

if [ $numbersInputVariables == "2" ] ; then
	echo "Numero di variabili corretto"
	url=$1
	defaultPath=$2
	echo "Verifico l'url immessa"
	checkURL
	ritorno=$?
	if [ $ritorno == "0" ] ; then 
		echo "L'url specificata risulta essere conforme"
	else
		echo "l'url specificata non risulta essere conforme, mi interrompo"
		exit 1
	fi

	echo "Verifico il path di download che esista"
	checkPathDownload
	ritorno=$?
	if [ $ritorno == "0" ] ; then 
		echo "Il path specificato risulta essere conforme"
	else
		# Per il momento ignoro la funzione che possa creare un path di download congruo con i vari ed eventuali storage a disposizione di proxmox 
		# sia locali che remoti che distribuiti, ignorando anche la gestione anticipata del check dello spazio libero in fase di download
		# per bloccare anticipatamente download impossibili da completarne lo scaricamento.
		echo "Il path specificato non risulta essere conforme, mi interrompo"
		exit 1
	fi
elif [ $numbersInputVariables == "1" ] ; then
	echo "Path download non specificato, utilizzo il default : $defaultPath"
	echo "Verifico l'url immessa"
	checkURL
	ritorno=$?
	if [ $ritorno == "0"] ; then 
		echo "L'url specificata risulta essere conforme"
		url=$1
	else
		echo "l'url specificata non risulta essere conforme, mi interrompo"
		exit 1
	fi
else
	echo "Numero di parametri non congruo con esecuzione corretta dello script, mi interrompo"
	exit 1
fi

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
