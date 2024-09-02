#!/bin/zsh

get_latest_snapshot_diff() {
	SNAPSHOTS=$(restic snapshots --json)

	PREVIOUS_SNAPSHOT=$(echo $SNAPSHOTS | jq -r ".[-2] | .short_id")
	LATEST_SNAPSHOT=$(echo $SNAPSHOTS | jq -r ".[-1] | .short_id")

	DIFF=$(restic diff $PREVIOUS_SNAPSHOT $LATEST_SNAPSHOT --json | tail -n 1)

	PRINT=$(echo $DIFF | jq -r '{ added: .added.files, changed: .changed_files, removed: .removed.files }')
	echo $PRINT
}

source ~/.zshrc

echo "Creating service backups"

# Create backips for services
bash /home/alastair/services/pihole/backup.sh
bash /home/alastair/services/photoprism/backup.sh
bash /home/alastair/services/monitoring/backup.sh

# Source the env vars for restic
source /home/alastair/services/restic/.env

echo "Backing up data to S3"

# Run the backup
restic --verbose backup \
	/mnt/raid/backup \
	/mnt/raid/docker-volumes/photoprism/originals \
	/mnt/raid/docker-volumes/photoprism/storage \
	/mnt/raid/docker-volumes/syncthing \
	--exclude-file=/home/alastair/services/restic/backup-ignore.txt

# restic backup will return a 0 if successful, or a 3 if it was successful but
# skipped a file due to a permissions error
SNAPSHOT_RESULT=$?

if [ $SNAPSHOT_RESULT -ne 0 ] && [ $SNAPSHOT_RESULT -ne 3 ]; then
  push "RPI-server" "Backup failed: Error creating snapshot"
  exit 1
fi

echo "Fetching backup diff"

DIFF=$(get_latest_snapshot_diff)

echo "Pruning old backups"

restic --verbose forget \
  --keep-within-daily 7d \
  --keep-within-weekly 1m \
  --keep-within-monthly 1y

PRUNE_RESULT=$?

if [ $PRUNE_RESULT -ne 0 ]; then
  push "RPI-server" "Backup failed: Error pruning snapshots"
  exit 1
fi

push "RPI-server" "$(echo $DIFF)"

