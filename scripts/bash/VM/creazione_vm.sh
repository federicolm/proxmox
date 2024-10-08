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
# 
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
