set PGUSER=postgres
set PGPASSWORD= clickbalance123

psql -U postgres -c "create TABLESPACE TB LOCATION 'C:\TB'"
psql -U postgres -c "create database launica2"

pg_restore.exe -i -h localhost -p 5030 -U postgres -d launica2 -v "respaldoLaUnica.backup"