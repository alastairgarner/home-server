#!/bin/bash

# Delete old backup files
rm /mnt/raid/backup/*

# Backup pihole config
docker exec -it pihole pihole -a -t /etc/backup/pihole-backup.tar.gz

# Source the env vars for restic
source /home/alastair/services/restic/.env

# Run the backup
# restic --verbose backup /mnt/raid/test-backup
