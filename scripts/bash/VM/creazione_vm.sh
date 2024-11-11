#!/bin/bash
#
# Obiettivo : creazione configurazione vm completa
#
# Parametri di input :
# 
# --agent [enabled=]<1|0> [,freeze-fs-on-backup=<1|0>]
# [,fstrim_cloned_disks=<1|0>] [,type=<virtio|isa>]
# Enable/disable communication with the QEMU Guest Agent and its properties.
# 
# --autostart <boolean> (default = 0)
# Automatic restart after crash (currently ignored).
#
# --balloon <integer> (0 - N)
# Amount of target RAM for the VM in MiB. Using zero disables the ballon driver
#
# --bios <ovmf | seabios> (default = seabios)
# Select BIOS implementation.
#
# --cores <integer> (1 - N) (default = 1)
# The number of cores per socket.
#
# --cpu [[cputype=]<string>] [,flags=<+FLAG[;-FLAG...]>]
# [,hidden=<1|0>] [,hv-vendor-id=<vendor-id>]
# [,phys-bits=<8-64|host>] [,reported-model=<enum>]
# Emulated CPU type.
#
# --cpulimit <number> (0 - 128) (default = 0)
# Limit of CPU usage.
#
# --cpuunits <integer> (1 - 262144) (default = cgroup v1: 1024, cgroup
# v2: 100)
# CPU weight for a VM, will be clamped to [1, 10000] in cgroup v2.
# N.B. : Durante la creazione tramite GUI il valore predefinito del "cpu units" è pari a 100
#
# --description <string>
# Description for the VM. Shown in the web-interface VM’s summary. This is saved as comment inside
# the configuration file.
#
# --hookscript <string>
# Script that will be executed during various steps in the vms lifetime.
#
# --hotplug <string> (default = network,disk,usb)
# Selectively enable hotplug features. This is a comma separated list of hotplug features: network, disk,
# cpu, memory, usb and cloudinit. Use 0 to disable hotplug completely. Using 1 as value is an alias for
# the default network,disk,usb. USB hotplugging is possible for guests with machine version >=
# 7.1 and ostype l26 or windows > 7. 
#
# --machine [[type=]<machine type>] [,viommu=<intel|virtio>]
# Specify the QEMU machine.
# tipologie di macchine : Q35 (versione più recente) oppure i440fx (default)
# viommu si può utilizzare esclusivamente se il tipo di macchine è impostato in Q35
# 
# Requisiti specifici della VM Intel vIOMMU:
#
# Indipendentemente dal fatto che si utilizzi una CPU Intel o AMD sull'host, è importante impostare 
# intel_iommu=on nei parametri del kernel delle VM.
#
# Per utilizzare Intel vIOMMU è necessario impostare q35 come tipo di macchina.
#
# Se tutti i requisiti sono soddisfatti, è possibile aggiungere viommu=intel al parametro macchina 
# nella configurazione della VM che dovrebbe essere in grado di passare attraverso i dispositivi PCI.
#
# Questa implementazione vIOMMU è più recente e non presenta tante limitazioni come Intel vIOMMU, 
# ma è attualmente meno utilizzata in produzione e meno documentata.
#
# Con VirtIO vIOMMU non c'è bisogno di impostare alcun parametro del kernel. 
# Non è nemmeno necessario usare q35 come tipo di macchina, ma è consigliabile se si desidera usare PCIe.
#
#
# --memory [current=]<integer>
# Memory properties.
#
# --name <string>
# Set a name for the VM. Only used on the configuration web interface 
#
# --net[n] [model=]<enum> [,bridge=<bridge>] [,firewall=<1|0>]
# [,link_down=<1|0>] [,macaddr=<XX:XX:XX:XX:XX:XX>] [,mtu=<integer>]
# [,queues=<integer>] [,rate=<number>] [,tag=<integer>]
# [,trunks=<vlanid[;vlanid...]>] [,<model>=<macaddr>]
# Specify network devices.
#
# --numa <boolean> (default = 0)
# Enable/disable NUMA.
#
# --onboot <boolean> (default = 0)
# Specifies whether a VM will be started during system bootup.
#
# --ostype <l24 | l26 | other | solaris | w2k | w2k3 | w2k8 | win10 |
# win11 | win7 | win8 | wvista | wxp>
# Specify guest operating system.
#
# --pool <string>
# Add the VM to the specified pool.
#
# --protection <boolean> (default = 0)
# Sets the protection flag of the VM. This will disable the remove VM and remove disk operations.
#
# --scsi[n] [file=]<volume> [,aio=<native|threads|io_uring>]
# [,backup=<1|0>] [,bps=<bps>] [,bps_max_length=<seconds>]
# [,bps_rd=<bps>] [,bps_rd_max_length=<seconds>] [,bps_wr=<bps>]
# [,bps_wr_max_length=<seconds>] [,cache=<enum>] [,cyls=<integer>]
# [,detect_zeroes=<1|0>] [,discard=<ignore|on>] [,format=<enum>]
# [,heads=<integer>] [,import-from=<source volume>] [,iops=<iops>]
# [,iops_max=<iops>] [,iops_max_length=<seconds>] [,iops_rd=<iops>]
# [,iops_rd_max=<iops>] [,iops_rd_max_length=<seconds>]
# [,iops_wr=<iops>] [,iops_wr_max=<iops>]
# [,iops_wr_max_length=<seconds>] [,iothread=<1|0>] [,mbps=<mbps>]
# [,mbps_max=<mbps>] [,mbps_rd=<mbps>] [,mbps_rd_max=<mbps>]
# [,mbps_wr=<mbps>] [,mbps_wr_max=<mbps>] [,media=<cdrom|disk>]
# [,product=<product>] [,queues=<integer>] [,replicate=<1|0>]
# [,rerror=<ignore|report|stop>] [,ro=<1|0>] [,scsiblock=<1|0>]
# [,secs=<integer>] [,serial=<serial>] [,shared=<1|0>]
# [,size=<DiskSize>] [,snapshot=<1|0>] [,ssd=<1|0>]
# [,trans=<none|lba|auto>] [,vendor=<vendor>] [,werror=<enum>]
# [,wwn=<wwn>]
# Use volume as SCSI hard disk or CD-ROM (n is 0 to 30). Use the special syntax STORAGE_ID:SIZE_IN_GiBto allocate a new volume. Use STORAGE_ID:0 and the import-from parameter to import from an existing volume.
# 
# --scsihw <lsi | lsi53c810 | megasas | pvscsi | virtio-scsi-pci |
# virtio-scsi-single> (default = lsi)
# SCSI controller model
# 
# 
# --smp <integer> (1 - N) (default = 1)
# The number of CPUs. Please use option -sockets instead.
# 
# --sockets <integer> (1 - N) (default = 1)
# The number of CPU sockets.
# 
# --spice_enhancements [foldersharing=<1|0>]
# [,videostreaming=<off|all|filter>]
# Configure additional enhancements for SPICE.
#
# --start <boolean> (default = 0)
# Start VM after it was created successfully.
#
# --storage <storage ID>
# Default storage. 
#
# --tags <string>
# Tags of the VM. This is only meta information.
#
# 
#
