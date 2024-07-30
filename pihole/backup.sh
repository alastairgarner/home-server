#!/bin/bash


docker exec -it pihole rm /etc/backup/pihole-backup.tar.gz
docker exec -it pihole pihole -a -t /etc/backup/pihole-backup.tar.gz
