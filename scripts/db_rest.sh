sudo pg_dropcluster 14 main --stop
sudo pg_createcluster 14 main
sudo systemctl restart postgresql.service
sudo -i -u postgres psql -c 'alter role postgres password null;'

sudo rm /etc/postgresql/14/main/pg_hba.conf
sudo rm /etc/postgresql/14/main/postgresql.conf
sudo cp /pg_hba.conf /etc/postgresql/14/main/pg_hba.conf
sudo cp /postgresql.conf /etc/postgresql/14/main/postgresql.conf
sudo chmod 777 /etc/postgresql/14/main/postgresql.conf
sudo chmod 777 /etc/postgresql/14/main/pg_hba.conf
sudo systemctl restart postgresql.service

cd /home/martin/projects/hivemind/haf/scripts
sudo ./setup_postgres.sh
sudo ./setup_db.sh --haf-db-admin=postgres

pg_restore            --section=pre-data  --disable-triggers    -h localhost -p 5432 -U postgres -d haf_block_log /home/martin/projects/hivemind/dump.dump
pg_restore -j 20 --section=data      --disable-triggers       -h localhost -p 5432 -U postgres              -d haf_block_log /home/martin/projects/hivemind/dump.dump
pg_restore   -h localhost -p 5432 -U postgres         --section=post-data --disable-triggers --clean --if-exists -d haf_block_log /home/martin/projects/hivemind/dump.dump
