#!/bin/bash

rm -f /mnt/raid/backup/grafana.db
cp /mnt/raid/docker-volumes/grafana/grafana.db /mnt/raid/backup/grafana.db
