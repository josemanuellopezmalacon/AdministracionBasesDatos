cluster name =  primer_cluster2;

# Define nodos.
node 1 admin conninfo = 'dbname = launica port = 5030 host =localhost user = postgres password=clickbalance123';
node 2 admin conninfo = 'dbname = postgres port = 5030 host = localhost user = postgres password=clickbalance123';

subscribe set(id=1,provider=1,receiver=2,forward=no);
