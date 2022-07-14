#!/bin/bash

#TODO : questa è solo una bozza, da migliorare pesantemente !

wget -P /var/lib/vz/template/cloudinit https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img ;

qm create 9000 --memory 2048 --cores 4 --net0 virtio,bridge=vmbr0 ;

qm importdisk 9000 /var/lib/vz/template/cloudinit/jammy-server-cloudimg-amd64.img local-lvm ;

qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0 ;

qm set 9000 --ide2 local-lvm:cloudinit ;

qm set 9000 --boot c --bootdisk scsi0 ;

qm set 9000 --serial0 socket --vga serial0 ;

qm template 9000 ;

qm clone 9000 123 --name ubuntu2 ;

qm set 123 --ipconfig0 ip=192.168.2.123/24,gw=192.168.2.1 --agent enabled=1 --sshkey /root/chiavissh/id_rsa_123.pub ;

qm resize 123 scsi0 10G ;

qm set 123 --sshkey /root/chiavissh/id_rsa_123.pub ;
qm set 123 --ciuser="ubuntu" --cipassword="password" ; #Pare non funzionare bene !
qm set 123 --cicustom "user=local:snippets/123.yaml" ;
