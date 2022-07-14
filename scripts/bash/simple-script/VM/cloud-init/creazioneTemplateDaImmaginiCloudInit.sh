#!/bin/bash

# TODO LIST
# -) creare un elenco di files in cui saranno presenti i links da cui scaricare le immagini cloudinit dei vari sistemi operativi scelti alle varie versioni
# -) in questo script ci sarà semplicemente un elenco generale degli OS 
# -) lo script una volta scaricata l'immagine ne creerà una vm e la trasformerà in un template in modo da poterlo poi clonare per le varie VM cloudinit da poter creare
# -) l'id dei template avranno un offset impostato nello script

offset=9000

lastIdUsed=$(qm list | grep -vi 'vmid' | awk '{print $1}' | sort | tail -1)

nextId=$(( lastIdUsed + 1 ))

defaultPath=/var/lib/vz/template/cloudinit

if [[ ! -d $defaultPath ]] ; then
	mkdir -p $defaultPath
	echo "La directory non esiste ed è stata creata"
else
	echo "La directory esiste !"
fi

readarray -d '' -t targets < <(grep --null -ri "http" ./files | awk -F ".cfg" '{print $2}')

#sizeList=${#listDownload[@]}

echo "dimensione array : ${#targets[@]}"

for str in ${targets[@]}; do
	my_arr=($(echo $str | tr "/" "\n"))
	nomeFile=${my_arr[-1]}
	echo "$nomeFile"
	if [[ ! -f $defaultPath/$nomeFile ]]; then
		echo "il file non esiste !"
		ls -la $defaultPath/$nomeFile
		wget -P $defaultPath $str
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
done

