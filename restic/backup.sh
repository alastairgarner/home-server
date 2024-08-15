#!/bin/bash

# Create backips for services
bash /home/alastair/services/pihole/backup.sh
bash /home/alastair/services/photoprism/backup.sh
bash /home/alastair/services/monitoring/backup.sh

# Source the env vars for restic
source /home/alastair/services/restic/.env

# Run the backup
restic --verbose backup \
	/mnt/raid/backup \
	/mnt/raid/photoprism/originals \
	/mnt/raid/photoprism/storage \
	--exclude-file=/home/alastair/services/restic/backup-ignore.txt
