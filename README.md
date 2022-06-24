# proxmox
Elenco di scripts e playbook per automatizzare varie funzionalità di proxmox e suo deployment


Elenco comandi da organizzare : 


##### Sezione bozze creazione vm con immagini cloud-init



##### Sezione bozze creazione vm con immagini iso

#!/bin/bash

numid=$(pvesh get /cluster/nextid)

node=$(cat /etc/hostname)

echo "Prossimo id utilizzabile : pallino-$numid-ciccio"

#TODO : sviluppare la casistica di più storage sia locali che remoti che cluster ceph e di più nodi in casi di cluster proxmox

#TODO 2 : per la casistica di creare una VM/CT/quello che ti pare, in un cluster, bisognerebbe prima sviluppare una parte di script che vada a leggere le configurazioni delle varie risorse ancora disponibili rispetto alle vm/ct/etc attualmente presenti nodo per nodo.

#TODO 3 : dal TODO 2 bisogna considerare 1 volta solamente le risorse condivise tipo storage remoti oppure cluster ceph in hyperconvergenza
pvesh create /nodes/$node/storage/local/content -filename vm-$numid-disk-0.qcow2 -format qcow2 -size 32G -vmid $numid

pvesh create /nodes/$node/qemu -vmid $numid \ 
        -memory 2048 \
        -sockets 1 \
        -cores 4 \
        -net0 e1000,bridge=vmbr1 \
        -ide0=local:$numid/vm-$numid-disk-0.qcow2 \
        -ide1=local:iso/CentOS-7-x86_64-Everything-2009.iso,media=cdrom

#qm create $numid --agent enabled=1,fstrim_cloned_disks=1 --autostart 1

echo "Fine esecuzione script"
echo "VM creata con id : $numid su nodo $node"



##### Sezione bozze script bash per scaricare immagini cloud-init


#!/bin/bash

dest_path=/var/lib/vz/template/iso/
name_img=focal-server-cloudimg-amd64.img
file=$dest_path$name_img

md5=fc64aea0a2b615eb930f5e9de9cb463d

echo "il file è : $file"

if [[ -f "$file"  ]]; then
        echo "$file esiste"
        md5new=$(md5sum $dest_path$name_img)
        if [[ "$md5" == "$md5new" ]]; then
                echo "gli md5 sono uguali"

        fi
fi
