#!/bin/bash
# ./vzbackup-rclone.sh rehydrate YYYY/MM/DD file_name_encrypted.bin

############ /START CONFIG
dumpdir="/backup/dump" # Set this to where your vzdump files are stored
MAX_AGE=6 # This is the age in days to keep local backup copies. Local backups older than this are deleted.
# Healthchecks url
url="https://hc-ping.com/p2bZY9PQh2clMe69UpcSSQ/proxmox_"
############ /END CONFIG

echo "*                       *"
echo "*                       *"
echo "Nombre total de parametres : $#"
echo "Liste des parametres (utilisant \$@) :"
for param in "$@"; do
  echo "Param : [$param]"
done
echo "*                       *"
echo "*                       *"

_bdir="$dumpdir"
rcloneroot="$dumpdir/rclone"
timepath="$(date +%Y)-$(date +%m)-$(date +%d)"
# shellcheck disable=SC2034
rclonedir="$rcloneroot/$timepath"
COMMAND=${1}
rehydrate=${2} #enter the date you want to rehydrate in the following format: YYYY/MM/DD
if [ -n "${3}" ];then
        CMDARCHIVE=$(echo "/${3}" | sed -e 's/\(.bin\)*$//g')
fi

if [[ ${COMMAND} == 'rehydrate' ]]; then
    #echo "Please enter the date you want to rehydrate in the following format: YYYY/MM/DD"
    #echo "For example, today would be: $timepath"
    #read -p 'Rehydrate Date => ' rehydrate
    rclone --config /root/.config/rclone/rclone.conf \
    --drive-chunk-size=32M copy "kdrivecrypt:/$rehydrate$CMDARCHIVE" "$dumpdir" \
    -v --stats=60s --transfers=16 --checkers=16
fi

if [[ ${COMMAND} == 'backup-start' ]]; then
    echo "==============STARTING BACKUP======================"
fi

if [[ ${COMMAND} == 'backup-start' ]]; then
    id=$3
    echo "Backing up dumps of id [$id]"

    echo "curling $url$id/start"
    curl --retry 3 "$url$id/start"

fi

if [[ ${COMMAND} == 'job-start' ]]; then
#    echo "Deleting backups older than $MAX_AGE days."
#    find $dumpdir -type f -mtime +$MAX_AGE -exec /bin/rm -f {} \;
fi

if [[ ${COMMAND} == 'backup-end' ]]; then
#    tarfile=$(ls -1t "$dumpdir" | head -n 1)
    id=$3

    rclone --config /root/.config/rclone/rclone.conf \
	sync "$dumpdir" "kchunk:$id" \
    	-v --stats=60s --transfers=16 --checkers=16 \
	--no-traverse --include "*$id*" --max-depth 1 \
	#--max-age 48h \
	 --progress

    result=$?
    urlToPing="$url$id"
    # Si le backup a échoué, on envoie le message d'erreur
    if [ "$result" -ne 0 ]; then
       urlToPing="${urlToPing}/$result"
    else
       # si le backup a fonctionné, on envoie le résultat OK
       echo "sending Healthchecks ping on $urlToPing"
       curl --retry 3 "$urlToPing"
   fi
fi

if [[ ${COMMAND} == 'job-end' ||  ${COMMAND} == 'job-abort' ]]; then
    echo "Job has ended or was aborted. Backing up main PVE configs"
    _tdir=${TMP_DIR:-/var/tmp}
    _tdir=$(mktemp -d "$_tdir/proxmox-XXXXXXXX")
    function clean_up {
        echo "Cleaning up"
        rm -rf "$_tdir"
    }
    trap clean_up EXIT
    _now=$(date +%Y-%m-%d.%H.%M.%S)
    _HOSTNAME=$(hostname -f)
    _filename1="$_tdir/proxmoxetc.$_now.tar"
    _filename2="$_tdir/proxmoxpve.$_now.tar"
    _filename3="$_tdir/proxmoxroot.$_now.tar"
    _filename4="$_tdir/proxmox_backup_$_HOSTNAME-$_now.tar.gz"

    echo "Tar files"
    # copy key system files
    tar --warning='no-file-ignored' -cPf "$_filename1" /etc/.
    tar --warning='no-file-ignored' -cPf "$_filename2" /var/lib/pve-cluster/.
    tar --warning='no-file-ignored' -cPf "$_filename3" /root/.

    echo "Compressing files"
    # archive the copied system files
    tar -cvzPf "$_filename4" "$_tdir"/*.tar

    # copy config archive to backup folder
    #mkdir -p $rclonedir
    cp -v "$_filename4" "$_bdir"/
    #cp -v $_filename4 $rclonedir/
    echo "rcloning $_filename4"
    #ls $rclonedir
    rclone --config /root/.config/rclone/rclone.conf \
    --drive-chunk-size=32M move "$_filename4" kdrivecrypt:/pve/"$timepath" \
    -v --stats=60s --transfers=16 --checkers=16

    #rm -rfv $rcloneroot
    echo "=============BACKUP FINISHED==============="
fi
