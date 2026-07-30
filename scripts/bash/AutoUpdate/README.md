# 🚀 Proxmox VE — Daily Automated Upgrade & Smart Kernel Manager

[![Bash Script](https://img.shields.io/badge/language-Bash-4EAA25.svg?style=flat-square)](https://www.gnu.org/software/bash/)
[![Proxmox VE](https://img.shields.io/badge/platform-Proxmox%20VE-E67E22.svg?style=flat-square)](https://www.proxmox.com)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg?style=flat-square)](https://www.gnu.org/licenses/gpl-3.0.html)

Un potente script Bash per l'automazione dei processi di manutenzione, pulizia e aggiornamento quotidiano dei nodi **Proxmox VE** (sia per installazioni fisiche che all'interno di macchine virtuali). 

Il core include una **logica avanzata e chirurgica per la gestione dei kernel**, meccanismi di **auto-healing** per sbloccare la coda APT in caso di pacchetti corrotti, e routine ricorsive di **pulizia d'emergenza** se lo spazio su disco scende sotto la soglia di guardia.

---

## 📌 Indice
- [Funzionalità Principali](#-funzionalità-principali)
- [Algoritmo di Gestione e Pulizia dei Kernel](#-algoritmo-di-gestione-e-pulizia-dei-kernel)
- [Architettura di Pulizia ed Emergenza](#-architettura-di-pulizia-ed-emergenza)
- [Requisiti e Prerequisiti](#-requisiti-e-prerequisiti)
- [Installazione e Schedulazione Systemd](#-installazione-e-schedulazione-systemd)
- [Logs e Debugging](#-logs-e-debugging)

---

## ✨ Funzionalità Principali

* **Gestione Chirurgica dei Kernel (Politica a 3 Livelli)**: Analizza ed esegue ad ogni avvio (anche se non ci sono aggiornamenti software) una pulizia mirata che conserva **esclusivamente**:
  1. Il kernel attualmente in esecuzione (`Running`).
  2. Il kernel immediatamente precedente a quello attuale (fallback di sicurezza).
  3. Tutte le versioni future/nuove appena installate in attesa di reboot.
* **Protezione dei Meta-Pacchetti**: Distingue accuratamente i pacchetti immagine del kernel (`-pve`) dai meta-pacchetti principali (es. `proxmox-kernel-7.0`), evitando che la purga interrompa i futuri aggiornamenti della serie.
* **Reportistica Email Integrale**: Invia via mail (tramite `mutt`) l'elenco completo e senza troncamenti di tutti i pacchetti da aggiornare o aggiornati, insieme a un resoconto dettagliato dei kernel rilevati, conservati e purgati.
* **Auto-Heal della Coda APT/DPKG**: Intercetta automaticamente meta-pacchetti kernel rimasti "appesi" o in stato di inconsistenza (`iU`, `iF`, `iR`, `iH`), applicando un `dpkg --purge --force-all` mirato per ripristinare il database senza alcun intervento manuale.
* **Allineamento Bootloader Agnostico**: Rileva dinamicamente se il nodo utilizza **GRUB** o **systemd-boot** (`proxmox-boot-tool`) applicando il corretto refresh dell'ambiente di boot al termine di ogni operazione sui kernel.

---

## 🧠 Algoritmo di Gestione e Pulizia dei Kernel

La funzione `cleanup_old_kernels` analizza la gerarchia delle versioni tramite un ordinamento numerico naturale (`sort -V`). 

```text
       [ Kernel Vecchi ]             [ Safety Fallback ]         [ Active Running ]         [ Nuovi / Futuri ]
 (Purgati completamente con -y)  ---> (Versione Precedente) ---> (Kernel uname -r) ---> (Installati ma no Reboot)
           [ELIMINATI]                   [CONSERVATO]               [CONSERVATO]               [CONSERVATI]
