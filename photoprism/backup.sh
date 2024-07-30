#!/bin/bash

docker exec photoprism rm -f /photoprism/backup/photoprism-db.sql
docker exec photoprism photoprism backup -i /photoprism/backup/photoprism-db.sql
docker exec photoprism chmod 644 /photoprism/backup/photoprism-db.sql
