#!/bin/bash
#
# Questo script va a cambiare lo stato di una vm oppure interrogarlo 
# N.B. : 
# - hibernate = qm suspend --todisk 1
# - stop = kill brutale della vm
# - shutdown = chiusura corretta della vm
# - reset = riavvio brutale della vm
# - start = avvio corretto della vm
# - reboot = riavvio corretto della vm
# - suspend = pausa della vm
# - resume = uscita dalla pausa della vm
# - status = interrogazione dello stato della vm

vmid=$1
stato=$2

if [[ "start" == "$2" || "shutdown" == "$2" || "reboot" == "$2" || "suspend" == "$2" || "hibernate" == "$2" || "stop" == "$2" || "reset" == "$2" || "resume" == "$2" || "status" == "$2" ]];then
	echo "Si vuole effettuare il comando di $stato sulla risorsa $1"
	qm $stato $vmid
	result=$?
	if [[ "$result" == 0 ]]; then
		echo "Comando eseguito correttamente"
	else
		echo "Il comando ha restituito un errore : $result"
	fi
else
	echo "Comando non riconosciuto"
	exit 1;
fi
