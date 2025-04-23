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
# Versione : 0.0.2
# Data : 17/04/2025
# Autore : Federico La Morgia <federico.lamorgia@gmail.com>
#



# Funzione per verificare la presenza di un file e il suo hash
verifica_file() {
  path="$1"
  hash_type="$2"
  expected_hash="$3"

  if [[ -f "$path" ]]; then
    echo "Il file '$path' esiste."
    calculated_hash=""
    if [[ "$hash_type" == "md5" ]]; then
      calculated_hash=$(md5sum "$path" | awk '{print $1}')
    elif [[ "$hash_type" == "sha256" ]]; then
      calculated_hash=$(sha256sum "$path" | awk '{print $1}')
    else
      echo "Tipo di hash non supportato: '$hash_type'. Uscita."
      exit 1
    fi

    if [[ "$calculated_hash" == "$expected_hash" ]]; then
      echo "L'hash del file corrisponde a '$expected_hash'."
      return 0 # File presente e hash corrispondente
    else
      echo "ATTENZIONE: L'hash del file non corrisponde. Sarà necessario scaricare nuovamente il file."
      return 1 # File presente ma hash diverso
    fi
  else
    echo "Il file '$path' non esiste."
    return 1 # File non presente
  fi
}

# Funzione per trovare lo storage ISO più libero
trova_storage_libero() {
  storage_list=($(pvesm status | grep iso | awk '{print $1}'))
  best_storage=""
  max_free=-1

  if [[ -z "${storage_list[@]}" ]]; then
    echo "Nessuno storage ISO disponibile."
    return
  fi

  for storage in "${storage_list[@]}"; do
    free_space=$(pvesm status "$storage" | awk '/Type: iso/ {print $6}')
    if [[ -n "$free_space" ]]; then
      free_space=$(echo "$free_space" | sed 's/GiB//' | awk '{print $1}')
      if [[ "$free_space" -gt "$max_free" ]]; then
        max_free="$free_space"
        best_storage="$storage"
      fi
    fi
  done

  if [[ -n "$best_storage" ]]; then
    echo "Lo storage ISO più libero è: '$best_storage' ($max_free GiB liberi)."
    echo "$best_storage"
  else
    echo "Impossibile determinare lo storage ISO più libero."
  fi
}

# Funzione per verificare lo spazio libero in uno storage specifico
verifica_spazio_libero() {
  storage="$1"
  required_space_mib="$2"

  free_space_gib=$(pvesm status "$storage" | awk '/Type: (.iso|images)/ {print $6}' | sed 's/GiB//' | awk '{print $1}')

  if [[ -n "$free_space_gib" ]]; then
    free_space_mib=$(echo "$free_space_gib * 1024" | bc)
    if [[ "$free_space_mib" -ge "$required_space_mib" ]]; then
      echo "Spazio libero sufficiente in '$storage'."
      return 0 # Spazio sufficiente
    else
      echo "Spazio libero insufficiente in '$storage' ($free_space_gib GiB). Richiesti almeno $(echo "$required_space_mib / 1024" | bc) GiB."
      return 1 # Spazio insufficiente
    fi
  else
    echo "Impossibile determinare lo spazio libero in '$storage'."
    return 1
  fi
}

# Funzione per scaricare il file
scarica_file() {
  url="$1"
  destination_path="$2"

  echo "Scaricamento del file da '$url' in '$destination_path'..."
  wget -O "$destination_path" "$url"
  if [[ $? -eq 0 ]]; then
    echo "Scaricamento completato con successo."
    return 0
  else
    echo "ERRORE durante il download del file."
    return 1
  fi
}

# --- Main script ---

# Verifica che siano forniti tutti i parametri necessari
if [[ -z "$1" || -z "$2" || -z "$3" || -z "$4" ]]; then
  echo "Utilizzo: $0 <path_destinazione> <tipo_hash (md5|sha256)> <hash_file> <url_download>"
  exit 1
fi

destination_path="$1"
hash_type="$2"
expected_hash="$3"
download_url="$4"

# Determina la directory di destinazione in base all'estensione del file
download_dir=""
if [[ "$destination_path" == *.qcow2 ]]; then
  download_dir="/var/lib/vz/template/cloudinit"
elif [[ "$destination_path" == *.iso ]]; then
  download_dir="/var/lib/vz/template/iso"
else
  echo "Estensione del file non riconosciuta. Uscita."
  exit 1
fi

# Costruisci il path completo del file nella directory di download
full_destination_path="$download_dir/$(basename "$destination_path")"

# Verifica se il file esiste già e se l'hash corrisponde
if verifica_file "$full_destination_path" "$hash_type" "$expected_hash"; then
  echo "Il file è già presente e l'hash corrisponde. Nessuna azione necessaria."
  exit 0
fi

# Se il file non esiste o l'hash non corrisponde, procedi con il download

# Ottieni la dimensione del file da scaricare (in byte)
content_length=$(curl -sI "$download_url" | grep -i "Content-Length" | awk '{print $2}')
if [[ -z "$content_length" || ! "$content_length" =~ ^[0-9]+$ ]]; then
  echo "Impossibile ottenere la dimensione del file da '$download_url'. Impossibile verificare lo spazio libero."
  # Continua comunque il download senza verifica dello spazio (potrebbe fallire)
else
  # Converti la dimensione in MiB per il confronto
  required_space_mib=$(echo "scale=2; $content_length / (1024 * 1024)" | bc)

  # Determina lo storage di destinazione
  target_storage=""
  if [[ "$download_dir" == "/var/lib/vz/template/iso" ]]; then
    target_storage=$(trova_storage_libero)
    if [[ -z "$target_storage" ]]; then
      echo "ERRORE: Impossibile trovare uno storage ISO disponibile. Uscita."
      exit 1
    fi
  else # /var/lib/vz/template/cloudinit (storage locale)
    # Presumiamo che lo storage locale sia 'local' (potrebbe variare)
    target_storage="local"
  fi

  echo "Lo storage di destinazione sarà: '$target_storage'."

  # Verifica lo spazio libero nello storage di destinazione
  if ! verifica_spazio_libero "$target_storage" "$required_space_mib"; then
    echo "ERRORE: Spazio libero insufficiente in '$target_storage'. Uscita."
    exit 1
  fi
fi

# Scarica il file
if scarica_file "$download_url" "$full_destination_path"; then
  echo "File scaricato con successo in '$full_destination_path'."
  # Opzionale: Verifica l'hash del file scaricato
  echo "Verifica dell'hash del file scaricato..."
  downloaded_hash=""
  if [[ "$hash_type" == "md5" ]]; then
    downloaded_hash=$(md5sum "$full_destination_path" | awk '{print $1}')
  elif [[ "$hash_type" == "sha256" ]]; then
    downloaded_hash=$(sha256sum "$full_destination_path" | awk '{print $1}')
  fi
  if [[ "$downloaded_hash" == "$expected_hash" ]]; then
    echo "L'hash del file scaricato corrisponde a '$expected_hash'."
  else
    echo "ATTENZIONE: L'hash del file scaricato ('$downloaded_hash') non corrisponde all'hash previsto ('$expected_hash')."
  fi
else
  echo "ERRORE: Il download del file non è riuscito."
  exit 1
fi

exit 0

