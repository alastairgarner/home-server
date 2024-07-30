#!/bin/bash

docker exec pihole rm -f /etc/backup/pihole-backup.tar.gz
docker exec pihole pihole -a -t /etc/backup/pihole-backup.tar.gz
