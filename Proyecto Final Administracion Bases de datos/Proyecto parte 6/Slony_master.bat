cluster name = primer_cluster2;

# Define nodos.
node 1 admin conninfo = 'dbname = launica port = 5030 host = localhost user = postgres password=clickbalance123';
node 2 admin conninfo = 'dbname = postgres port = 5030  host = localhost user = postgres password=clickbalance123';

# Inicializar Cluster.
init cluster (id = 1, comment = 'Nodo maestro');

# agrupa tablas en SETS.
create set (id = 1, origin = 1, comment = 'tablas de conjunto');

set add table(set id = 1, origin = 1, id = 1, fully qualified name = 'comercial.agente', comment='clientes');
set add table(set id = 1, origin = 1, id = 2, fully qualified name = 'cxc.clientes', comment='agentes');

store node(id = 2, comment = 'Nodo Esclavo', event node = 1);

store path(server = 1, client = 2, conninfo = 'dbname = launica port = 5030 host =localhost user = postgres password=clickbalance123');
store path(server = 2, client = 1, conninfo = 'dbname = postgres port = 5030 host =localhost user = postgres password=clickbalance123');

store listen (origin=1,provider=1,receiver=2);
store listen (origin=2,provider=2,receiver=1);

