#!/bin/bash

url="https://hc-ping.com/p2bZY9PQh2clMe69UpcSSQ/backup-proxmox"
curl --retry 3 "$url/start"

# Récupérer les IDs des conteneurs LXC
lxc_ids=($(ls /backup/dump/vzdump-lxc-* | grep -oP 'vzdump-lxc-\K\d+(?=-202)' | sort -u))

# Récupérer les IDs des machines virtuelles (VM)
vm_ids=($(ls /backup/dump/vzdump-qemu-* | grep -oP 'vzdump-qemu-\K\d+(?=-202)' | sort -u))

# Concaténer les deux tableaux
all_ids=("${lxc_ids[@]}" "${vm_ids[@]}")

# Afficher tous les IDs
echo "Tous les IDs:"
for id in "${all_ids[@]}"; do
  echo "$id"


  rclone --config /root/.config/rclone/rclone.conf \
    --drive-chunk-size=32M copy /backup/dump kdrivecrypt:$id/ \
    -v --stats=60s --transfers=16 --checkers=16 \
    --no-traverse -v --progress --include "*$id*" --max-depth 1

done

# Envoi de l'info de fin de backup avec le code retour de la commande rclone
curl --retry 3 "$url/$?"
