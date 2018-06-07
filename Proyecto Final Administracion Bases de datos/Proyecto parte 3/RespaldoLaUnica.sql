--
-- PostgreSQL database dump
--

-- Dumped from database version 10.4
-- Dumped by pg_dump version 10.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: _primer_cluster2; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA _primer_cluster2;


ALTER SCHEMA _primer_cluster2 OWNER TO postgres;

--
-- Name: comercial; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA comercial;


ALTER SCHEMA comercial OWNER TO postgres;

--
-- Name: cxc; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA cxc;


ALTER SCHEMA cxc OWNER TO postgres;

--
-- Name: inventarios; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA inventarios;


ALTER SCHEMA inventarios OWNER TO postgres;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: vactables; Type: TYPE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TYPE _primer_cluster2.vactables AS (
	nspname name,
	relname name
);


ALTER TYPE _primer_cluster2.vactables OWNER TO postgres;

--
-- Name: TYPE vactables; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TYPE _primer_cluster2.vactables IS 'used as return type for SRF function TablesToVacuum';


--
-- Name: add_empty_table_to_replication(integer, integer, text, text, text, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.add_empty_table_to_replication(p_set_id integer, p_tab_id integer, p_nspname text, p_tabname text, p_idxname text, p_comment text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare

  prec record;
  v_origin int4;
  v_isorigin boolean;
  v_fqname text;
  v_query text;
  v_rows integer;
  v_idxname text;

begin
-- Need to validate that the set exists; the set will tell us if this is the origin
  select set_origin into v_origin from "_primer_cluster2".sl_set where set_id = p_set_id;
  if not found then
	raise exception 'add_empty_table_to_replication: set % not found!', p_set_id;
  end if;

-- Need to be aware of whether or not this node is origin for the set
   v_isorigin := ( v_origin = "_primer_cluster2".getLocalNodeId('_primer_cluster2') );

   v_fqname := '"' || p_nspname || '"."' || p_tabname || '"';
-- Take out a lock on the table
   v_query := 'lock ' || v_fqname || ';';
   execute v_query;

   if v_isorigin then
	-- On the origin, verify that the table is empty, failing if it has any tuples
        v_query := 'select 1 as tuple from ' || v_fqname || ' limit 1;';
	execute v_query into prec;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
	if v_rows = 0 then
		raise notice 'add_empty_table_to_replication: table % empty on origin - OK', v_fqname;
	else
		raise exception 'add_empty_table_to_replication: table % contained tuples on origin node %', v_fqname, v_origin;
	end if;
   else
	-- On other nodes, TRUNCATE the table
        v_query := 'truncate ' || v_fqname || ';';
	execute v_query;
   end if;
-- If p_idxname is NULL, then look up the PK index, and RAISE EXCEPTION if one does not exist
   if p_idxname is NULL then
	select c2.relname into prec from pg_catalog.pg_index i, pg_catalog.pg_class c1, pg_catalog.pg_class c2, pg_catalog.pg_namespace n where i.indrelid = c1.oid and i.indexrelid = c2.oid and c1.relname = p_tabname and i.indisprimary and n.nspname = p_nspname and n.oid = c1.relnamespace;
	if not found then
		raise exception 'add_empty_table_to_replication: table % has no primary key and no candidate specified!', v_fqname;
	else
		v_idxname := prec.relname;
	end if;
   else
	v_idxname := p_idxname;
   end if;
   return "_primer_cluster2".setAddTable_int(p_set_id, p_tab_id, v_fqname, v_idxname, p_comment);
end
$$;


ALTER FUNCTION _primer_cluster2.add_empty_table_to_replication(p_set_id integer, p_tab_id integer, p_nspname text, p_tabname text, p_idxname text, p_comment text) OWNER TO postgres;

--
-- Name: FUNCTION add_empty_table_to_replication(p_set_id integer, p_tab_id integer, p_nspname text, p_tabname text, p_idxname text, p_comment text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.add_empty_table_to_replication(p_set_id integer, p_tab_id integer, p_nspname text, p_tabname text, p_idxname text, p_comment text) IS 'Verify that a table is empty, and add it to replication.  
tab_idxname is optional - if NULL, then we use the primary key.

Note that this function is to be run within an EXECUTE SCRIPT script,
so it runs at the right place in the transaction stream on all
nodes.';


--
-- Name: add_missing_table_field(text, text, text, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.add_missing_table_field(p_namespace text, p_table text, p_field text, p_type text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_row       record;
  v_query     text;
BEGIN
  if not "_primer_cluster2".check_table_field_exists(p_namespace, p_table, p_field) then
    raise notice 'Upgrade table %.% - add field %', p_namespace, p_table, p_field;
    v_query := 'alter table ' || p_namespace || '.' || p_table || ' add column ';
    v_query := v_query || p_field || ' ' || p_type || ';';
    execute v_query;
    return 't';
  else
    return 'f';
  end if;
END;$$;


ALTER FUNCTION _primer_cluster2.add_missing_table_field(p_namespace text, p_table text, p_field text, p_type text) OWNER TO postgres;

--
-- Name: FUNCTION add_missing_table_field(p_namespace text, p_table text, p_field text, p_type text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.add_missing_table_field(p_namespace text, p_table text, p_field text, p_type text) IS 'Add a column of a given type to a table if it is missing';


--
-- Name: addpartiallogindices(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.addpartiallogindices() RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_current_status	int4;
	v_log			int4;
	v_dummy		record;
	v_dummy2	record;
	idef 		text;
	v_count		int4;
        v_iname         text;
	v_ilen int4;
	v_maxlen int4;
BEGIN
	v_count := 0;
	select last_value into v_current_status from "_primer_cluster2".sl_log_status;

	-- If status is 2 or 3 --> in process of cleanup --> unsafe to create indices
	if v_current_status in (2, 3) then
		return 0;
	end if;

	if v_current_status = 0 then   -- Which log should get indices?
		v_log := 2;
	else
		v_log := 1;
	end if;
--                                       PartInd_test_db_sl_log_2-node-1
	-- Add missing indices...
	for v_dummy in select distinct set_origin from "_primer_cluster2".sl_set loop
            v_iname := 'PartInd_primer_cluster2_sl_log_' || v_log::text || '-node-' 
			|| v_dummy.set_origin::text;
	   -- raise notice 'Consider adding partial index % on sl_log_%', v_iname, v_log;
	   -- raise notice 'schema: [_primer_cluster2] tablename:[sl_log_%]', v_log;
            select * into v_dummy2 from pg_catalog.pg_indexes where tablename = 'sl_log_' || v_log::text and  indexname = v_iname;
            if not found then
		-- raise notice 'index was not found - add it!';
        v_iname := 'PartInd_primer_cluster2_sl_log_' || v_log::text || '-node-' || v_dummy.set_origin::text;
		v_ilen := pg_catalog.length(v_iname);
		v_maxlen := pg_catalog.current_setting('max_identifier_length'::text)::int4;
                if v_ilen > v_maxlen then
		   raise exception 'Length of proposed index name [%] > max_identifier_length [%] - cluster name probably too long', v_ilen, v_maxlen;
		end if;

		idef := 'create index "' || v_iname || 
                        '" on "_primer_cluster2".sl_log_' || v_log::text || ' USING btree(log_txid) where (log_origin = ' || v_dummy.set_origin::text || ');';
		execute idef;
		v_count := v_count + 1;
            else
                -- raise notice 'Index % already present - skipping', v_iname;
            end if;
	end loop;

	-- Remove unneeded indices...
	for v_dummy in select indexname from pg_catalog.pg_indexes i where i.tablename = 'sl_log_' || v_log::text and
                       i.indexname like ('PartInd_primer_cluster2_sl_log_' || v_log::text || '-node-%') and
                       not exists (select 1 from "_primer_cluster2".sl_set where
				i.indexname = 'PartInd_primer_cluster2_sl_log_' || v_log::text || '-node-' || set_origin::text)
	loop
		-- raise notice 'Dropping obsolete index %d', v_dummy.indexname;
		idef := 'drop index "_primer_cluster2"."' || v_dummy.indexname || '";';
		execute idef;
		v_count := v_count - 1;
	end loop;
	return v_count;
END
$$;


ALTER FUNCTION _primer_cluster2.addpartiallogindices() OWNER TO postgres;

--
-- Name: FUNCTION addpartiallogindices(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.addpartiallogindices() IS 'Add partial indexes, if possible, to the unused sl_log_? table for
all origin nodes, and drop any that are no longer needed.

This function presently gets run any time set origins are manipulated
(FAILOVER, STORE SET, MOVE SET, DROP SET), as well as each time the
system switches between sl_log_1 and sl_log_2.';


--
-- Name: agg_text_sum(text, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.agg_text_sum(txt_before text, txt_new text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
  c_delim text;
BEGIN
    c_delim = ',';
	IF (txt_before IS NULL or txt_before='') THEN
	   RETURN txt_new;
	END IF;
	RETURN txt_before || c_delim || txt_new;
END;
$$;


ALTER FUNCTION _primer_cluster2.agg_text_sum(txt_before text, txt_new text) OWNER TO postgres;

--
-- Name: FUNCTION agg_text_sum(txt_before text, txt_new text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.agg_text_sum(txt_before text, txt_new text) IS 'An accumulator function used by the slony string_agg function to
aggregate rows into a string';


--
-- Name: altertableaddtriggers(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.altertableaddtriggers(p_tab_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_no_id				int4;
	v_tab_row			record;
	v_tab_fqname		text;
	v_tab_attkind		text;
	v_n					int4;
	v_trec	record;
	v_tgbad	boolean;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Get our local node ID
	-- ----
	v_no_id := "_primer_cluster2".getLocalNodeId('_primer_cluster2');

	-- ----
	-- Get the sl_table row and the current origin of the table. 
	-- ----
	select T.tab_reloid, T.tab_set, T.tab_idxname, 
			S.set_origin, PGX.indexrelid,
			"_primer_cluster2".slon_quote_brute(PGN.nspname) || '.' ||
			"_primer_cluster2".slon_quote_brute(PGC.relname) as tab_fqname
			into v_tab_row
			from "_primer_cluster2".sl_table T, "_primer_cluster2".sl_set S,
				"pg_catalog".pg_class PGC, "pg_catalog".pg_namespace PGN,
				"pg_catalog".pg_index PGX, "pg_catalog".pg_class PGXC
			where T.tab_id = p_tab_id
				and T.tab_set = S.set_id
				and T.tab_reloid = PGC.oid
				and PGC.relnamespace = PGN.oid
				and PGX.indrelid = T.tab_reloid
				and PGX.indexrelid = PGXC.oid
				and PGXC.relname = T.tab_idxname
				for update;
	if not found then
		raise exception 'Slony-I: alterTableAddTriggers(): Table with id % not found', p_tab_id;
	end if;
	v_tab_fqname = v_tab_row.tab_fqname;

	v_tab_attkind := "_primer_cluster2".determineAttKindUnique(v_tab_row.tab_fqname, 
						v_tab_row.tab_idxname);

	execute 'lock table ' || v_tab_fqname || ' in access exclusive mode';

	-- ----
	-- Create the log and the deny access triggers
	-- ----
	execute 'create trigger "_primer_cluster2_logtrigger"' || 
			' after insert or update or delete on ' ||
			v_tab_fqname || ' for each row execute procedure "_primer_cluster2".logTrigger (' ||
                               pg_catalog.quote_literal('_primer_cluster2') || ',' || 
				pg_catalog.quote_literal(p_tab_id::text) || ',' || 
				pg_catalog.quote_literal(v_tab_attkind) || ');';

	execute 'create trigger "_primer_cluster2_denyaccess" ' || 
			'before insert or update or delete on ' ||
			v_tab_fqname || ' for each row execute procedure ' ||
			'"_primer_cluster2".denyAccess (' || pg_catalog.quote_literal('_primer_cluster2') || ');';

	perform "_primer_cluster2".alterTableAddTruncateTrigger(v_tab_fqname, p_tab_id);

	perform "_primer_cluster2".alterTableConfigureTriggers (p_tab_id);
	return p_tab_id;
end;
$$;


ALTER FUNCTION _primer_cluster2.altertableaddtriggers(p_tab_id integer) OWNER TO postgres;

--
-- Name: FUNCTION altertableaddtriggers(p_tab_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.altertableaddtriggers(p_tab_id integer) IS 'alterTableAddTriggers(tab_id)

Adds the log and deny access triggers to a replicated table.';


--
-- Name: altertableaddtruncatetrigger(text, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.altertableaddtruncatetrigger(i_fqtable text, i_tabid integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
		execute 'create trigger "_primer_cluster2_truncatetrigger" ' ||
				' before truncate on ' || i_fqtable || ' for each statement execute procedure ' ||
				'"_primer_cluster2".log_truncate(' || i_tabid || ');';
		execute 'create trigger "_primer_cluster2_truncatedeny" ' ||
				' before truncate on ' || i_fqtable || ' for each statement execute procedure ' ||
				'"_primer_cluster2".deny_truncate();';
		return 1;
end
$$;


ALTER FUNCTION _primer_cluster2.altertableaddtruncatetrigger(i_fqtable text, i_tabid integer) OWNER TO postgres;

--
-- Name: FUNCTION altertableaddtruncatetrigger(i_fqtable text, i_tabid integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.altertableaddtruncatetrigger(i_fqtable text, i_tabid integer) IS 'function to add TRUNCATE TRIGGER';


--
-- Name: altertableconfiguretriggers(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.altertableconfiguretriggers(p_tab_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_no_id				int4;
	v_tab_row			record;
	v_tab_fqname		text;
	v_n					int4;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Get our local node ID
	-- ----
	v_no_id := "_primer_cluster2".getLocalNodeId('_primer_cluster2');

	-- ----
	-- Get the sl_table row and the current tables origin.
	-- ----
	select T.tab_reloid, T.tab_set,
			S.set_origin, PGX.indexrelid,
			"_primer_cluster2".slon_quote_brute(PGN.nspname) || '.' ||
			"_primer_cluster2".slon_quote_brute(PGC.relname) as tab_fqname
			into v_tab_row
			from "_primer_cluster2".sl_table T, "_primer_cluster2".sl_set S,
				"pg_catalog".pg_class PGC, "pg_catalog".pg_namespace PGN,
				"pg_catalog".pg_index PGX, "pg_catalog".pg_class PGXC
			where T.tab_id = p_tab_id
				and T.tab_set = S.set_id
				and T.tab_reloid = PGC.oid
				and PGC.relnamespace = PGN.oid
				and PGX.indrelid = T.tab_reloid
				and PGX.indexrelid = PGXC.oid
				and PGXC.relname = T.tab_idxname
				for update;
	if not found then
		raise exception 'Slony-I: alterTableConfigureTriggers(): Table with id % not found', p_tab_id;
	end if;
	v_tab_fqname = v_tab_row.tab_fqname;

	-- ----
	-- Configuration depends on the origin of the table
	-- ----
	if v_tab_row.set_origin = v_no_id then
		-- ----
		-- On the origin the log trigger is configured like a default
		-- user trigger and the deny access trigger is disabled.
		-- ----
		execute 'alter table ' || v_tab_fqname ||
				' enable trigger "_primer_cluster2_logtrigger"';
		execute 'alter table ' || v_tab_fqname ||
				' disable trigger "_primer_cluster2_denyaccess"';
        perform "_primer_cluster2".alterTableConfigureTruncateTrigger(v_tab_fqname,
				'enable', 'disable');
	else
		-- ----
		-- On a replica the log trigger is disabled and the
		-- deny access trigger fires in origin session role.
		-- ----
		execute 'alter table ' || v_tab_fqname ||
				' disable trigger "_primer_cluster2_logtrigger"';
		execute 'alter table ' || v_tab_fqname ||
				' enable trigger "_primer_cluster2_denyaccess"';
        perform "_primer_cluster2".alterTableConfigureTruncateTrigger(v_tab_fqname,
				'disable', 'enable');

	end if;

	return p_tab_id;
end;
$$;


ALTER FUNCTION _primer_cluster2.altertableconfiguretriggers(p_tab_id integer) OWNER TO postgres;

--
-- Name: FUNCTION altertableconfiguretriggers(p_tab_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.altertableconfiguretriggers(p_tab_id integer) IS 'alterTableConfigureTriggers (tab_id)

Set the enable/disable configuration for the replication triggers
according to the origin of the set.';


--
-- Name: altertableconfiguretruncatetrigger(text, text, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.altertableconfiguretruncatetrigger(i_fqname text, i_log_stat text, i_deny_stat text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
		execute 'alter table ' || i_fqname || ' ' || i_log_stat ||
				' trigger "_primer_cluster2_truncatetrigger";';
		execute 'alter table ' || i_fqname || ' ' || i_deny_stat ||
				' trigger "_primer_cluster2_truncatedeny";';
		return 1;
end $$;


ALTER FUNCTION _primer_cluster2.altertableconfiguretruncatetrigger(i_fqname text, i_log_stat text, i_deny_stat text) OWNER TO postgres;

--
-- Name: FUNCTION altertableconfiguretruncatetrigger(i_fqname text, i_log_stat text, i_deny_stat text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.altertableconfiguretruncatetrigger(i_fqname text, i_log_stat text, i_deny_stat text) IS 'Configure the truncate triggers according to origin status.';


--
-- Name: altertabledroptriggers(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.altertabledroptriggers(p_tab_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_no_id				int4;
	v_tab_row			record;
	v_tab_fqname		text;
	v_n					int4;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Get our local node ID
	-- ----
	v_no_id := "_primer_cluster2".getLocalNodeId('_primer_cluster2');

	-- ----
	-- Get the sl_table row and the current tables origin.
	-- ----
	select T.tab_reloid, T.tab_set,
			S.set_origin, PGX.indexrelid,
			"_primer_cluster2".slon_quote_brute(PGN.nspname) || '.' ||
			"_primer_cluster2".slon_quote_brute(PGC.relname) as tab_fqname
			into v_tab_row
			from "_primer_cluster2".sl_table T, "_primer_cluster2".sl_set S,
				"pg_catalog".pg_class PGC, "pg_catalog".pg_namespace PGN,
				"pg_catalog".pg_index PGX, "pg_catalog".pg_class PGXC
			where T.tab_id = p_tab_id
				and T.tab_set = S.set_id
				and T.tab_reloid = PGC.oid
				and PGC.relnamespace = PGN.oid
				and PGX.indrelid = T.tab_reloid
				and PGX.indexrelid = PGXC.oid
				and PGXC.relname = T.tab_idxname
				for update;
	if not found then
		raise exception 'Slony-I: alterTableDropTriggers(): Table with id % not found', p_tab_id;
	end if;
	v_tab_fqname = v_tab_row.tab_fqname;

	execute 'lock table ' || v_tab_fqname || ' in access exclusive mode';

	-- ----
	-- Drop both triggers
	-- ----
	execute 'drop trigger "_primer_cluster2_logtrigger" on ' || 
			v_tab_fqname;

	execute 'drop trigger "_primer_cluster2_denyaccess" on ' || 
			v_tab_fqname;
				
	perform "_primer_cluster2".alterTableDropTruncateTrigger(v_tab_fqname, p_tab_id);

	return p_tab_id;
end;
$$;


ALTER FUNCTION _primer_cluster2.altertabledroptriggers(p_tab_id integer) OWNER TO postgres;

--
-- Name: FUNCTION altertabledroptriggers(p_tab_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.altertabledroptriggers(p_tab_id integer) IS 'alterTableDropTriggers (tab_id)

Remove the log and deny access triggers from a table.';


--
-- Name: altertabledroptruncatetrigger(text, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.altertabledroptruncatetrigger(i_fqtable text, i_tabid integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
		execute 'drop trigger "_primer_cluster2_truncatetrigger" ' ||
				' on ' || i_fqtable || ';';
		execute 'drop trigger "_primer_cluster2_truncatedeny" ' ||
				' on ' || i_fqtable || ';';
		return 1;
end
$$;


ALTER FUNCTION _primer_cluster2.altertabledroptruncatetrigger(i_fqtable text, i_tabid integer) OWNER TO postgres;

--
-- Name: FUNCTION altertabledroptruncatetrigger(i_fqtable text, i_tabid integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.altertabledroptruncatetrigger(i_fqtable text, i_tabid integer) IS 'function to drop TRUNCATE TRIGGER';


--
-- Name: check_table_field_exists(text, text, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.check_table_field_exists(p_namespace text, p_table text, p_field text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
	return exists (
			select 1 from "information_schema".columns
				where table_schema = p_namespace
				and table_name = p_table
				and column_name = p_field
		);
END;$$;


ALTER FUNCTION _primer_cluster2.check_table_field_exists(p_namespace text, p_table text, p_field text) OWNER TO postgres;

--
-- Name: FUNCTION check_table_field_exists(p_namespace text, p_table text, p_field text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.check_table_field_exists(p_namespace text, p_table text, p_field text) IS 'Check if a table has a specific attribute';


--
-- Name: check_unconfirmed_log(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.check_unconfirmed_log() RETURNS boolean
    LANGUAGE plpgsql
    AS $$
declare
	v_rc		bool = false;
	v_error		bool = false;
	v_origin	integer;
	v_allconf	bigint;
	v_allsnap	txid_snapshot;
	v_count		bigint;
begin
	--
	-- Loop over all nodes that are the origin of at least one set
	--
	for v_origin in select distinct set_origin as no_id
			from "_primer_cluster2".sl_set loop
		--
		-- Per origin determine which is the highest event seqno
		-- that is confirmed by all subscribers to any of the
		-- origins sets.
		--
		select into v_allconf min(max_seqno) from (
				select con_received, max(con_seqno) as max_seqno
					from "_primer_cluster2".sl_confirm
					where con_origin = v_origin
					and con_received in (
						select distinct sub_receiver
							from "_primer_cluster2".sl_set as SET,
								"_primer_cluster2".sl_subscribe as SUB
							where SET.set_id = SUB.sub_set
							and SET.set_origin = v_origin
						)
					group by con_received
			) as maxconfirmed;
		if not found then
			raise NOTICE 'check_unconfirmed_log(): cannot determine highest ev_seqno for node % confirmed by all subscribers', v_origin;
			v_error = true;
			continue;
		end if;

		--
		-- Get the txid snapshot that corresponds with that event
		--
		select into v_allsnap ev_snapshot
			from "_primer_cluster2".sl_event
			where ev_origin = v_origin
			and ev_seqno = v_allconf;
		if not found then
			raise NOTICE 'check_unconfirmed_log(): cannot find event %,% in sl_event', v_origin, v_allconf;
			v_error = true;
			continue;
		end if;

		--
		-- Count the number of log rows that appeard after that event.
		--
		select into v_count count(*) from (
			select 1 from "_primer_cluster2".sl_log_1
				where log_origin = v_origin
				and log_txid >= "pg_catalog".txid_snapshot_xmax(v_allsnap)
			union all
			select 1 from "_primer_cluster2".sl_log_1
				where log_origin = v_origin
				and log_txid in (
					select * from "pg_catalog".txid_snapshot_xip(v_allsnap)
				)
			union all
			select 1 from "_primer_cluster2".sl_log_2
				where log_origin = v_origin
				and log_txid >= "pg_catalog".txid_snapshot_xmax(v_allsnap)
			union all
			select 1 from "_primer_cluster2".sl_log_2
				where log_origin = v_origin
				and log_txid in (
					select * from "pg_catalog".txid_snapshot_xip(v_allsnap)
				)
		) as cnt;

		if v_count > 0 then
			raise NOTICE 'check_unconfirmed_log(): origin % has % log rows that have not propagated to all subscribers yet', v_origin, v_count;
			v_rc = true;
		end if;
	end loop;

	if v_error then
		raise EXCEPTION 'check_unconfirmed_log(): aborting due to previous inconsistency';
	end if;

	return v_rc;
end;
$$;


ALTER FUNCTION _primer_cluster2.check_unconfirmed_log() OWNER TO postgres;

--
-- Name: checkmoduleversion(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.checkmoduleversion() RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
  moduleversion	text;
begin
  select into moduleversion "_primer_cluster2".getModuleVersion();
  if moduleversion <> '2.2.6' then
      raise exception 'Slonik version: 2.2.6 != Slony-I version in PG build %',
             moduleversion;
  end if;
  return null;
end;$$;


ALTER FUNCTION _primer_cluster2.checkmoduleversion() OWNER TO postgres;

--
-- Name: FUNCTION checkmoduleversion(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.checkmoduleversion() IS 'Inline test function that verifies that slonik request for STORE
NODE/INIT CLUSTER is being run against a conformant set of
schema/functions.';


--
-- Name: cleanupevent(interval); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.cleanupevent(p_interval interval) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_max_row	record;
	v_min_row	record;
	v_max_sync	int8;
	v_origin	int8;
	v_seqno		int8;
	v_xmin		bigint;
	v_rc            int8;
begin
	-- ----
	-- First remove all confirmations where origin/receiver no longer exist
	-- ----
	delete from "_primer_cluster2".sl_confirm
				where con_origin not in (select no_id from "_primer_cluster2".sl_node);
	delete from "_primer_cluster2".sl_confirm
				where con_received not in (select no_id from "_primer_cluster2".sl_node);
	-- ----
	-- Next remove all but the oldest confirm row per origin,receiver pair.
	-- Ignore confirmations that are younger than 10 minutes. We currently
	-- have an not confirmed suspicion that a possibly lost transaction due
	-- to a server crash might have been visible to another session, and
	-- that this led to log data that is needed again got removed.
	-- ----
	for v_max_row in select con_origin, con_received, max(con_seqno) as con_seqno
				from "_primer_cluster2".sl_confirm
				where con_timestamp < (CURRENT_TIMESTAMP - p_interval)
				group by con_origin, con_received
	loop
		delete from "_primer_cluster2".sl_confirm
				where con_origin = v_max_row.con_origin
				and con_received = v_max_row.con_received
				and con_seqno < v_max_row.con_seqno;
	end loop;

	-- ----
	-- Then remove all events that are confirmed by all nodes in the
	-- whole cluster up to the last SYNC
	-- ----
	for v_min_row in select con_origin, min(con_seqno) as con_seqno
				from "_primer_cluster2".sl_confirm
				group by con_origin
	loop
		select coalesce(max(ev_seqno), 0) into v_max_sync
				from "_primer_cluster2".sl_event
				where ev_origin = v_min_row.con_origin
				and ev_seqno <= v_min_row.con_seqno
				and ev_type = 'SYNC';
		if v_max_sync > 0 then
			delete from "_primer_cluster2".sl_event
					where ev_origin = v_min_row.con_origin
					and ev_seqno < v_max_sync;
		end if;
	end loop;

	-- ----
	-- If cluster has only one node, then remove all events up to
	-- the last SYNC - Bug #1538
        -- http://gborg.postgresql.org/project/slony1/bugs/bugupdate.php?1538
	-- ----

	select * into v_min_row from "_primer_cluster2".sl_node where
			no_id <> "_primer_cluster2".getLocalNodeId('_primer_cluster2') limit 1;
	if not found then
		select ev_origin, ev_seqno into v_min_row from "_primer_cluster2".sl_event
		where ev_origin = "_primer_cluster2".getLocalNodeId('_primer_cluster2')
		order by ev_origin desc, ev_seqno desc limit 1;
		raise notice 'Slony-I: cleanupEvent(): Single node - deleting events < %', v_min_row.ev_seqno;
			delete from "_primer_cluster2".sl_event
			where
				ev_origin = v_min_row.ev_origin and
				ev_seqno < v_min_row.ev_seqno;

        end if;

	if exists (select * from "pg_catalog".pg_class c, "pg_catalog".pg_namespace n, "pg_catalog".pg_attribute a where c.relname = 'sl_seqlog' and n.oid = c.relnamespace and a.attrelid = c.oid and a.attname = 'oid') then
                execute 'alter table "_primer_cluster2".sl_seqlog set without oids;';
	end if;		
	-- ----
	-- Also remove stale entries from the nodelock table.
	-- ----
	perform "_primer_cluster2".cleanupNodelock();

	-- ----
	-- Find the eldest event left, for each origin
	-- ----
    for v_origin, v_seqno, v_xmin in
	select ev_origin, ev_seqno, "pg_catalog".txid_snapshot_xmin(ev_snapshot) from "_primer_cluster2".sl_event
          where (ev_origin, ev_seqno) in (select ev_origin, min(ev_seqno) from "_primer_cluster2".sl_event where ev_type = 'SYNC' group by ev_origin)
	loop
		delete from "_primer_cluster2".sl_seqlog where seql_origin = v_origin and seql_ev_seqno < v_seqno;
		delete from "_primer_cluster2".sl_log_script where log_origin = v_origin and log_txid < v_xmin;
    end loop;
	
	v_rc := "_primer_cluster2".logswitch_finish();
	if v_rc = 0 then   -- no switch in progress
		perform "_primer_cluster2".logswitch_start();
	end if;

	return 0;
end;
$$;


ALTER FUNCTION _primer_cluster2.cleanupevent(p_interval interval) OWNER TO postgres;

--
-- Name: FUNCTION cleanupevent(p_interval interval); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.cleanupevent(p_interval interval) IS 'cleaning old data out of sl_confirm, sl_event.  Removes all but the
last sl_confirm row per (origin,receiver), and then removes all events
that are confirmed by all nodes in the whole cluster up to the last
SYNC.';


--
-- Name: cleanupnodelock(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.cleanupnodelock() RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_row		record;
begin
	for v_row in select nl_nodeid, nl_conncnt, nl_backendpid
			from "_primer_cluster2".sl_nodelock
			for update
	loop
		if "_primer_cluster2".killBackend(v_row.nl_backendpid, 'NULL') < 0 then
			raise notice 'Slony-I: cleanup stale sl_nodelock entry for pid=%',
					v_row.nl_backendpid;
			delete from "_primer_cluster2".sl_nodelock where
					nl_nodeid = v_row.nl_nodeid and
					nl_conncnt = v_row.nl_conncnt;
		end if;
	end loop;

	return 0;
end;
$$;


ALTER FUNCTION _primer_cluster2.cleanupnodelock() OWNER TO postgres;

--
-- Name: FUNCTION cleanupnodelock(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.cleanupnodelock() IS 'Clean up stale entries when restarting slon';


--
-- Name: clonenodefinish(integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.clonenodefinish(p_no_id integer, p_no_provider integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_row			record;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	perform "pg_catalog".setval('"_primer_cluster2".sl_local_node_id', p_no_id);
	perform "_primer_cluster2".resetSession();
	for v_row in select sub_set from "_primer_cluster2".sl_subscribe
			where sub_receiver = p_no_id
	loop
		perform "_primer_cluster2".updateReloid(v_row.sub_set, p_no_id);
	end loop;

	perform "_primer_cluster2".RebuildListenEntries();

	delete from "_primer_cluster2".sl_confirm
		where con_received = p_no_id;
	insert into "_primer_cluster2".sl_confirm
		(con_origin, con_received, con_seqno, con_timestamp)
		select con_origin, p_no_id, con_seqno, con_timestamp
		from "_primer_cluster2".sl_confirm
		where con_received = p_no_provider;
	insert into "_primer_cluster2".sl_confirm
		(con_origin, con_received, con_seqno, con_timestamp)
		select p_no_provider, p_no_id, 
				(select max(ev_seqno) from "_primer_cluster2".sl_event
					where ev_origin = p_no_provider), current_timestamp;

	return 0;
end;
$$;


ALTER FUNCTION _primer_cluster2.clonenodefinish(p_no_id integer, p_no_provider integer) OWNER TO postgres;

--
-- Name: FUNCTION clonenodefinish(p_no_id integer, p_no_provider integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.clonenodefinish(p_no_id integer, p_no_provider integer) IS 'Internal part of cloneNodePrepare().';


--
-- Name: clonenodeprepare(integer, integer, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.clonenodeprepare(p_no_id integer, p_no_provider integer, p_no_comment text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
begin
	perform "_primer_cluster2".cloneNodePrepare_int (p_no_id, p_no_provider, p_no_comment);
	return  "_primer_cluster2".createEvent('_primer_cluster2', 'CLONE_NODE',
									p_no_id::text, p_no_provider::text,
									p_no_comment::text);
end;
$$;


ALTER FUNCTION _primer_cluster2.clonenodeprepare(p_no_id integer, p_no_provider integer, p_no_comment text) OWNER TO postgres;

--
-- Name: FUNCTION clonenodeprepare(p_no_id integer, p_no_provider integer, p_no_comment text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.clonenodeprepare(p_no_id integer, p_no_provider integer, p_no_comment text) IS 'Prepare for cloning a node.';


--
-- Name: clonenodeprepare_int(integer, integer, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.clonenodeprepare_int(p_no_id integer, p_no_provider integer, p_no_comment text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
   v_dummy int4;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	update "_primer_cluster2".sl_node set
	       no_active = np.no_active,
	       no_comment = np.no_comment,
	       no_failed = np.no_failed
	       from "_primer_cluster2".sl_node np
	       where np.no_id = p_no_provider
	       and sl_node.no_id = p_no_id;
	if not found then
	   insert into "_primer_cluster2".sl_node
		(no_id, no_active, no_comment,no_failed)
		select p_no_id, no_active, p_no_comment, no_failed
		from "_primer_cluster2".sl_node
		where no_id = p_no_provider;
	end if;

       insert into "_primer_cluster2".sl_path
	    (pa_server, pa_client, pa_conninfo, pa_connretry)
	    select pa_server, p_no_id, '<event pending>', pa_connretry
	    from "_primer_cluster2".sl_path
	    where pa_client = p_no_provider
	    and (pa_server, p_no_id) not in (select pa_server, pa_client
	    	    from "_primer_cluster2".sl_path);

       insert into "_primer_cluster2".sl_path
	    (pa_server, pa_client, pa_conninfo, pa_connretry)
	    select p_no_id, pa_client, '<event pending>', pa_connretry
	    from "_primer_cluster2".sl_path
	    where pa_server = p_no_provider
	    and (p_no_id, pa_client) not in (select pa_server, pa_client
	    	    from "_primer_cluster2".sl_path);

	insert into "_primer_cluster2".sl_subscribe
		(sub_set, sub_provider, sub_receiver, sub_forward, sub_active)
		select sub_set, sub_provider, p_no_id, sub_forward, sub_active
		from "_primer_cluster2".sl_subscribe
		where sub_receiver = p_no_provider;

	insert into "_primer_cluster2".sl_confirm
		(con_origin, con_received, con_seqno, con_timestamp)
		select con_origin, p_no_id, con_seqno, con_timestamp
		from "_primer_cluster2".sl_confirm
		where con_received = p_no_provider;

	perform "_primer_cluster2".RebuildListenEntries();

	return 0;
end;
$$;


ALTER FUNCTION _primer_cluster2.clonenodeprepare_int(p_no_id integer, p_no_provider integer, p_no_comment text) OWNER TO postgres;

--
-- Name: FUNCTION clonenodeprepare_int(p_no_id integer, p_no_provider integer, p_no_comment text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.clonenodeprepare_int(p_no_id integer, p_no_provider integer, p_no_comment text) IS 'Internal part of cloneNodePrepare().';


--
-- Name: component_state(text, integer, integer, integer, text, timestamp with time zone, bigint, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.component_state(i_actor text, i_pid integer, i_node integer, i_conn_pid integer, i_activity text, i_starttime timestamp with time zone, i_event bigint, i_eventtype text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
	-- Trim out old state for this component
	if not exists (select 1 from "_primer_cluster2".sl_components where co_actor = i_actor) then
	   insert into "_primer_cluster2".sl_components 
             (co_actor, co_pid, co_node, co_connection_pid, co_activity, co_starttime, co_event, co_eventtype)
	   values 
              (i_actor, i_pid, i_node, i_conn_pid, i_activity, i_starttime, i_event, i_eventtype);
	else
	   update "_primer_cluster2".sl_components 
              set
                 co_connection_pid = i_conn_pid, co_activity = i_activity, co_starttime = i_starttime, co_event = i_event,
                 co_eventtype = i_eventtype
              where co_actor = i_actor 
	      	    and co_starttime < i_starttime;
	end if;
	return 1;
end $$;


ALTER FUNCTION _primer_cluster2.component_state(i_actor text, i_pid integer, i_node integer, i_conn_pid integer, i_activity text, i_starttime timestamp with time zone, i_event bigint, i_eventtype text) OWNER TO postgres;

--
-- Name: FUNCTION component_state(i_actor text, i_pid integer, i_node integer, i_conn_pid integer, i_activity text, i_starttime timestamp with time zone, i_event bigint, i_eventtype text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.component_state(i_actor text, i_pid integer, i_node integer, i_conn_pid integer, i_activity text, i_starttime timestamp with time zone, i_event bigint, i_eventtype text) IS 'Store state of a Slony component.  Useful for monitoring';


--
-- Name: copyfields(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.copyfields(p_tab_id integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
	result text;
	prefix text;
	prec record;
begin
	result := '';
	prefix := '(';   -- Initially, prefix is the opening paren

	for prec in select "_primer_cluster2".slon_quote_input(a.attname) as column from "_primer_cluster2".sl_table t, pg_catalog.pg_attribute a where t.tab_id = p_tab_id and t.tab_reloid = a.attrelid and a.attnum > 0 and a.attisdropped = false order by attnum
	loop
		result := result || prefix || prec.column;
		prefix := ',';   -- Subsequently, prepend columns with commas
	end loop;
	result := result || ')';
	return result;
end;
$$;


ALTER FUNCTION _primer_cluster2.copyfields(p_tab_id integer) OWNER TO postgres;

--
-- Name: FUNCTION copyfields(p_tab_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.copyfields(p_tab_id integer) IS 'Return a string consisting of what should be appended to a COPY statement
to specify fields for the passed-in tab_id.  

In PG versions > 7.3, this looks like (field1,field2,...fieldn)';


--
-- Name: createevent(name, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text) RETURNS bigint
    LANGUAGE c
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_createEvent';


ALTER FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text) OWNER TO postgres;

--
-- Name: FUNCTION createevent(p_cluster_name name, p_event_type text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text) IS 'FUNCTION createEvent (cluster_name, ev_type [, ev_data [...]])

Create an sl_event entry';


--
-- Name: createevent(name, text, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text) RETURNS bigint
    LANGUAGE c
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_createEvent';


ALTER FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text) OWNER TO postgres;

--
-- Name: FUNCTION createevent(p_cluster_name name, p_event_type text, ev_data1 text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text) IS 'FUNCTION createEvent (cluster_name, ev_type [, ev_data [...]])

Create an sl_event entry';


--
-- Name: createevent(name, text, text, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text) RETURNS bigint
    LANGUAGE c
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_createEvent';


ALTER FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text) OWNER TO postgres;

--
-- Name: FUNCTION createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text) IS 'FUNCTION createEvent (cluster_name, ev_type [, ev_data [...]])

Create an sl_event entry';


--
-- Name: createevent(name, text, text, text, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text) RETURNS bigint
    LANGUAGE c
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_createEvent';


ALTER FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text) OWNER TO postgres;

--
-- Name: FUNCTION createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text) IS 'FUNCTION createEvent (cluster_name, ev_type [, ev_data [...]])

Create an sl_event entry';


--
-- Name: createevent(name, text, text, text, text, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text, ev_data4 text) RETURNS bigint
    LANGUAGE c
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_createEvent';


ALTER FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text, ev_data4 text) OWNER TO postgres;

--
-- Name: FUNCTION createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text, ev_data4 text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text, ev_data4 text) IS 'FUNCTION createEvent (cluster_name, ev_type [, ev_data [...]])

Create an sl_event entry';


--
-- Name: createevent(name, text, text, text, text, text, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text, ev_data4 text, ev_data5 text) RETURNS bigint
    LANGUAGE c
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_createEvent';


ALTER FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text, ev_data4 text, ev_data5 text) OWNER TO postgres;

--
-- Name: FUNCTION createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text, ev_data4 text, ev_data5 text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text, ev_data4 text, ev_data5 text) IS 'FUNCTION createEvent (cluster_name, ev_type [, ev_data [...]])

Create an sl_event entry';


--
-- Name: createevent(name, text, text, text, text, text, text, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text, ev_data4 text, ev_data5 text, ev_data6 text) RETURNS bigint
    LANGUAGE c
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_createEvent';


ALTER FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text, ev_data4 text, ev_data5 text, ev_data6 text) OWNER TO postgres;

--
-- Name: FUNCTION createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text, ev_data4 text, ev_data5 text, ev_data6 text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text, ev_data4 text, ev_data5 text, ev_data6 text) IS 'FUNCTION createEvent (cluster_name, ev_type [, ev_data [...]])

Create an sl_event entry';


--
-- Name: createevent(name, text, text, text, text, text, text, text, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text, ev_data4 text, ev_data5 text, ev_data6 text, ev_data7 text) RETURNS bigint
    LANGUAGE c
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_createEvent';


ALTER FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text, ev_data4 text, ev_data5 text, ev_data6 text, ev_data7 text) OWNER TO postgres;

--
-- Name: FUNCTION createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text, ev_data4 text, ev_data5 text, ev_data6 text, ev_data7 text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text, ev_data4 text, ev_data5 text, ev_data6 text, ev_data7 text) IS 'FUNCTION createEvent (cluster_name, ev_type [, ev_data [...]])

Create an sl_event entry';


--
-- Name: createevent(name, text, text, text, text, text, text, text, text, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text, ev_data4 text, ev_data5 text, ev_data6 text, ev_data7 text, ev_data8 text) RETURNS bigint
    LANGUAGE c
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_createEvent';


ALTER FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text, ev_data4 text, ev_data5 text, ev_data6 text, ev_data7 text, ev_data8 text) OWNER TO postgres;

--
-- Name: FUNCTION createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text, ev_data4 text, ev_data5 text, ev_data6 text, ev_data7 text, ev_data8 text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.createevent(p_cluster_name name, p_event_type text, ev_data1 text, ev_data2 text, ev_data3 text, ev_data4 text, ev_data5 text, ev_data6 text, ev_data7 text, ev_data8 text) IS 'FUNCTION createEvent (cluster_name, ev_type [, ev_data [...]])

Create an sl_event entry';


--
-- Name: ddlcapture(text, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.ddlcapture(p_statement text, p_nodes text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	c_local_node	integer;
	c_found_origin	boolean;
	c_node			text;
	c_cmdargs		text[];
	c_nodeargs      text;
	c_delim         text;
begin
	c_local_node := "_primer_cluster2".getLocalNodeId('_primer_cluster2');

	c_cmdargs = array_append('{}'::text[], p_statement);
	c_nodeargs = '';
	if p_nodes is not null then
		c_found_origin := 'f';
		-- p_nodes list needs to consist of a list of nodes that exist
		-- and that include the current node ID
		for c_node in select trim(node) from
				pg_catalog.regexp_split_to_table(p_nodes, ',') as node loop
			if not exists 
					(select 1 from "_primer_cluster2".sl_node 
					where no_id = (c_node::integer)) then
				raise exception 'ddlcapture(%,%) - node % does not exist!', 
					p_statement, p_nodes, c_node;
		   end if;

		   if c_local_node = (c_node::integer) then
		   	  c_found_origin := 't';
		   end if;
		   if length(c_nodeargs)>0 then
		   	  c_nodeargs = c_nodeargs ||','|| c_node;
		   else
				c_nodeargs=c_node;
			end if;
	   end loop;

		if not c_found_origin then
			raise exception 
				'ddlcapture(%,%) - origin node % not included in ONLY ON list!',
				p_statement, p_nodes, c_local_node;
       end if;
    end if;
	c_cmdargs = array_append(c_cmdargs,c_nodeargs);
	c_delim=',';
	c_cmdargs = array_append(c_cmdargs, 

           (select "_primer_cluster2".string_agg( seq_id::text || c_delim
		   || c_local_node ||
		    c_delim || seq_last_value)
		    FROM (
		       select seq_id,
           	   seq_last_value from "_primer_cluster2".sl_seqlastvalue
           	   where seq_origin = c_local_node) as FOO
			where NOT "_primer_cluster2".seqtrack(seq_id,seq_last_value) is NULL));
	insert into "_primer_cluster2".sl_log_script
			(log_origin, log_txid, log_actionseq, log_cmdtype, log_cmdargs)
		values 
			(c_local_node, pg_catalog.txid_current(), 
			nextval('"_primer_cluster2".sl_action_seq'), 'S', c_cmdargs);
	execute p_statement;
	return currval('"_primer_cluster2".sl_action_seq');
end;
$$;


ALTER FUNCTION _primer_cluster2.ddlcapture(p_statement text, p_nodes text) OWNER TO postgres;

--
-- Name: FUNCTION ddlcapture(p_statement text, p_nodes text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.ddlcapture(p_statement text, p_nodes text) IS 'Capture an SQL statement (usually DDL) that is to be literally replayed on subscribers';


--
-- Name: ddlscript_complete(text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.ddlscript_complete(p_nodes text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	c_local_node	integer;
	c_found_origin	boolean;
	c_node			text;
	c_cmdargs		text[];
begin
	c_local_node := "_primer_cluster2".getLocalNodeId('_primer_cluster2');

	c_cmdargs = '{}'::text[];
	if p_nodes is not null then
		c_found_origin := 'f';
		-- p_nodes list needs to consist o a list of nodes that exist
		-- and that include the current node ID
		for c_node in select trim(node) from
				pg_catalog.regexp_split_to_table(p_nodes, ',') as node loop
			if not exists 
					(select 1 from "_primer_cluster2".sl_node 
					where no_id = (c_node::integer)) then
				raise exception 'ddlcapture(%,%) - node % does not exist!', 
					p_statement, p_nodes, c_node;
		   end if;

		   if c_local_node = (c_node::integer) then
		   	  c_found_origin := 't';
		   end if;

		   c_cmdargs = array_append(c_cmdargs, c_node);
	   end loop;

		if not c_found_origin then
			raise exception 
				'ddlScript_complete(%) - origin node % not included in ONLY ON list!',
				p_nodes, c_local_node;
       end if;
    end if;

	perform "_primer_cluster2".ddlScript_complete_int();

	insert into "_primer_cluster2".sl_log_script
			(log_origin, log_txid, log_actionseq, log_cmdtype, log_cmdargs)
		values 
			(c_local_node, pg_catalog.txid_current(), 
			nextval('"_primer_cluster2".sl_action_seq'), 's', c_cmdargs);

	return currval('"_primer_cluster2".sl_action_seq');
end;
$$;


ALTER FUNCTION _primer_cluster2.ddlscript_complete(p_nodes text) OWNER TO postgres;

--
-- Name: FUNCTION ddlscript_complete(p_nodes text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.ddlscript_complete(p_nodes text) IS 'ddlScript_complete(set_id, script, only_on_node)

After script has run on origin, this fixes up relnames and
log trigger arguments and inserts the "fire ddlScript_complete_int()
log row into sl_log_script.';


--
-- Name: ddlscript_complete_int(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.ddlscript_complete_int() RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
	perform "_primer_cluster2".updateRelname();
	perform "_primer_cluster2".repair_log_triggers(true);
	return 0;
end;
$$;


ALTER FUNCTION _primer_cluster2.ddlscript_complete_int() OWNER TO postgres;

--
-- Name: FUNCTION ddlscript_complete_int(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.ddlscript_complete_int() IS 'ddlScript_complete_int()

Complete processing the DDL_SCRIPT event.';


--
-- Name: decode_tgargs(bytea); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.decode_tgargs(bytea) RETURNS text[]
    LANGUAGE c SECURITY DEFINER
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_slon_decode_tgargs';


ALTER FUNCTION _primer_cluster2.decode_tgargs(bytea) OWNER TO postgres;

--
-- Name: FUNCTION decode_tgargs(bytea); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.decode_tgargs(bytea) IS 'Translates the contents of pg_trigger.tgargs to an array of text arguments';


--
-- Name: deny_truncate(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.deny_truncate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
	declare
		r_role text;
	begin
		-- Ignore this call if session_replication_role = 'local'
		select into r_role setting
			from pg_catalog.pg_settings where name = 'session_replication_role';
		if r_role = 'local' then
			return NULL;
		end if;

		raise exception 'truncation of replicated table forbidden on subscriber node';
    end
$$;


ALTER FUNCTION _primer_cluster2.deny_truncate() OWNER TO postgres;

--
-- Name: FUNCTION deny_truncate(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.deny_truncate() IS 'trigger function run when a replicated table receives a TRUNCATE request';


--
-- Name: denyaccess(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.denyaccess() RETURNS trigger
    LANGUAGE c SECURITY DEFINER
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_denyAccess';


ALTER FUNCTION _primer_cluster2.denyaccess() OWNER TO postgres;

--
-- Name: FUNCTION denyaccess(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.denyaccess() IS 'Trigger function to prevent modifications to a table on a subscriber';


--
-- Name: determineattkindunique(text, name); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.determineattkindunique(p_tab_fqname text, p_idx_name name) RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
	v_tab_fqname_quoted	text default '';
	v_idx_name_quoted	text;
	v_idxrow		record;
	v_attrow		record;
	v_i				integer;
	v_attno			int2;
	v_attkind		text default '';
	v_attfound		bool;
begin
	v_tab_fqname_quoted := "_primer_cluster2".slon_quote_input(p_tab_fqname);
	v_idx_name_quoted := "_primer_cluster2".slon_quote_brute(p_idx_name);
	--
	-- Ensure that the table exists
	--
	if (select PGC.relname
				from "pg_catalog".pg_class PGC,
					"pg_catalog".pg_namespace PGN
				where "_primer_cluster2".slon_quote_brute(PGN.nspname) || '.' ||
					"_primer_cluster2".slon_quote_brute(PGC.relname) = v_tab_fqname_quoted
					and PGN.oid = PGC.relnamespace) is null then
		raise exception 'Slony-I: table % not found', v_tab_fqname_quoted;
	end if;

	--
	-- Lookup the tables primary key or the specified unique index
	--
	if p_idx_name isnull then
		raise exception 'Slony-I: index name must be specified';
	else
		select PGXC.relname, PGX.indexrelid, PGX.indkey
				into v_idxrow
				from "pg_catalog".pg_class PGC,
					"pg_catalog".pg_namespace PGN,
					"pg_catalog".pg_index PGX,
					"pg_catalog".pg_class PGXC
				where "_primer_cluster2".slon_quote_brute(PGN.nspname) || '.' ||
					"_primer_cluster2".slon_quote_brute(PGC.relname) = v_tab_fqname_quoted
					and PGN.oid = PGC.relnamespace
					and PGX.indrelid = PGC.oid
					and PGX.indexrelid = PGXC.oid
					and PGX.indisunique
					and "_primer_cluster2".slon_quote_brute(PGXC.relname) = v_idx_name_quoted;
		if not found then
			raise exception 'Slony-I: table % has no unique index %',
					v_tab_fqname_quoted, v_idx_name_quoted;
		end if;
	end if;

	--
	-- Loop over the tables attributes and check if they are
	-- index attributes. If so, add a "k" to the return value,
	-- otherwise add a "v".
	--
	for v_attrow in select PGA.attnum, PGA.attname
			from "pg_catalog".pg_class PGC,
			    "pg_catalog".pg_namespace PGN,
				"pg_catalog".pg_attribute PGA
			where "_primer_cluster2".slon_quote_brute(PGN.nspname) || '.' ||
			    "_primer_cluster2".slon_quote_brute(PGC.relname) = v_tab_fqname_quoted
				and PGN.oid = PGC.relnamespace
				and PGA.attrelid = PGC.oid
				and not PGA.attisdropped
				and PGA.attnum > 0
			order by attnum
	loop
		v_attfound = 'f';

		v_i := 0;
		loop
			select indkey[v_i] into v_attno from "pg_catalog".pg_index
					where indexrelid = v_idxrow.indexrelid;
			if v_attno isnull or v_attno = 0 then
				exit;
			end if;
			if v_attrow.attnum = v_attno then
				v_attfound = 't';
				exit;
			end if;
			v_i := v_i + 1;
		end loop;

		if v_attfound then
			v_attkind := v_attkind || 'k';
		else
			v_attkind := v_attkind || 'v';
		end if;
	end loop;

	-- Strip off trailing v characters as they are not needed by the logtrigger
	v_attkind := pg_catalog.rtrim(v_attkind, 'v');

	--
	-- Return the resulting attkind
	--
	return v_attkind;
end;
$$;


ALTER FUNCTION _primer_cluster2.determineattkindunique(p_tab_fqname text, p_idx_name name) OWNER TO postgres;

--
-- Name: FUNCTION determineattkindunique(p_tab_fqname text, p_idx_name name); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.determineattkindunique(p_tab_fqname text, p_idx_name name) IS 'determineAttKindUnique (tab_fqname, indexname)

Given a tablename, return the Slony-I specific attkind (used for the
log trigger) of the table. Use the specified unique index or the
primary key (if indexname is NULL).';


--
-- Name: determineidxnameunique(text, name); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.determineidxnameunique(p_tab_fqname text, p_idx_name name) RETURNS name
    LANGUAGE plpgsql
    AS $$
declare
	v_tab_fqname_quoted	text default '';
	v_idxrow		record;
begin
	v_tab_fqname_quoted := "_primer_cluster2".slon_quote_input(p_tab_fqname);
	--
	-- Ensure that the table exists
	--
	if (select PGC.relname
				from "pg_catalog".pg_class PGC,
					"pg_catalog".pg_namespace PGN
				where "_primer_cluster2".slon_quote_brute(PGN.nspname) || '.' ||
					"_primer_cluster2".slon_quote_brute(PGC.relname) = v_tab_fqname_quoted
					and PGN.oid = PGC.relnamespace) is null then
		raise exception 'Slony-I: determineIdxnameUnique(): table % not found', v_tab_fqname_quoted;
	end if;

	--
	-- Lookup the tables primary key or the specified unique index
	--
	if p_idx_name isnull then
		select PGXC.relname
				into v_idxrow
				from "pg_catalog".pg_class PGC,
					"pg_catalog".pg_namespace PGN,
					"pg_catalog".pg_index PGX,
					"pg_catalog".pg_class PGXC
				where "_primer_cluster2".slon_quote_brute(PGN.nspname) || '.' ||
					"_primer_cluster2".slon_quote_brute(PGC.relname) = v_tab_fqname_quoted
					and PGN.oid = PGC.relnamespace
					and PGX.indrelid = PGC.oid
					and PGX.indexrelid = PGXC.oid
					and PGX.indisprimary;
		if not found then
			raise exception 'Slony-I: table % has no primary key',
					v_tab_fqname_quoted;
		end if;
	else
		select PGXC.relname
				into v_idxrow
				from "pg_catalog".pg_class PGC,
					"pg_catalog".pg_namespace PGN,
					"pg_catalog".pg_index PGX,
					"pg_catalog".pg_class PGXC
				where "_primer_cluster2".slon_quote_brute(PGN.nspname) || '.' ||
					"_primer_cluster2".slon_quote_brute(PGC.relname) = v_tab_fqname_quoted
					and PGN.oid = PGC.relnamespace
					and PGX.indrelid = PGC.oid
					and PGX.indexrelid = PGXC.oid
					and PGX.indisunique
					and "_primer_cluster2".slon_quote_brute(PGXC.relname) = "_primer_cluster2".slon_quote_input(p_idx_name);
		if not found then
			raise exception 'Slony-I: table % has no unique index %',
					v_tab_fqname_quoted, p_idx_name;
		end if;
	end if;

	--
	-- Return the found index name
	--
	return v_idxrow.relname;
end;
$$;


ALTER FUNCTION _primer_cluster2.determineidxnameunique(p_tab_fqname text, p_idx_name name) OWNER TO postgres;

--
-- Name: FUNCTION determineidxnameunique(p_tab_fqname text, p_idx_name name); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.determineidxnameunique(p_tab_fqname text, p_idx_name name) IS 'FUNCTION determineIdxnameUnique (tab_fqname, indexname)

Given a tablename, tab_fqname, check that the unique index, indexname,
exists or return the primary key index name for the table.  If there
is no unique index, it raises an exception.';


--
-- Name: disable_indexes_on_table(oid); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.disable_indexes_on_table(i_oid oid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
	-- Setting pg_class.relhasindex to false will cause copy not to
	-- maintain any indexes. At the end of the copy we will reenable
	-- them and reindex the table. This bulk creating of indexes is
	-- faster.

	update pg_catalog.pg_class set relhasindex ='f' where oid = i_oid;
	return 1;
end $$;


ALTER FUNCTION _primer_cluster2.disable_indexes_on_table(i_oid oid) OWNER TO postgres;

--
-- Name: FUNCTION disable_indexes_on_table(i_oid oid); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.disable_indexes_on_table(i_oid oid) IS 'disable indexes on the specified table.
Used during subscription process to suppress indexes, which allows
COPY to go much faster.

This may be set as a SECURITY DEFINER in order to eliminate the need
for superuser access by Slony-I.
';


--
-- Name: disablenode(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.disablenode(p_no_id integer) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
begin
	-- **** TODO ****
	raise exception 'Slony-I: disableNode() not implemented';
end;
$$;


ALTER FUNCTION _primer_cluster2.disablenode(p_no_id integer) OWNER TO postgres;

--
-- Name: FUNCTION disablenode(p_no_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.disablenode(p_no_id integer) IS 'process DISABLE_NODE event for node no_id

NOTE: This is not yet implemented!';


--
-- Name: disablenode_int(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.disablenode_int(p_no_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
	-- **** TODO ****
	raise exception 'Slony-I: disableNode_int() not implemented';
end;
$$;


ALTER FUNCTION _primer_cluster2.disablenode_int(p_no_id integer) OWNER TO postgres;

--
-- Name: droplisten(integer, integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.droplisten(p_li_origin integer, p_li_provider integer, p_li_receiver integer) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
begin
	perform "_primer_cluster2".dropListen_int(p_li_origin, 
			p_li_provider, p_li_receiver);
	
	return  "_primer_cluster2".createEvent ('_primer_cluster2', 'DROP_LISTEN',
			p_li_origin::text, p_li_provider::text, p_li_receiver::text);
end;
$$;


ALTER FUNCTION _primer_cluster2.droplisten(p_li_origin integer, p_li_provider integer, p_li_receiver integer) OWNER TO postgres;

--
-- Name: FUNCTION droplisten(p_li_origin integer, p_li_provider integer, p_li_receiver integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.droplisten(p_li_origin integer, p_li_provider integer, p_li_receiver integer) IS 'dropListen (li_origin, li_provider, li_receiver)

Generate the DROP_LISTEN event.';


--
-- Name: droplisten_int(integer, integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.droplisten_int(p_li_origin integer, p_li_provider integer, p_li_receiver integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	delete from "_primer_cluster2".sl_listen
			where li_origin = p_li_origin
			and li_provider = p_li_provider
			and li_receiver = p_li_receiver;
	if found then
		return 1;
	else
		return 0;
	end if;
end;
$$;


ALTER FUNCTION _primer_cluster2.droplisten_int(p_li_origin integer, p_li_provider integer, p_li_receiver integer) OWNER TO postgres;

--
-- Name: FUNCTION droplisten_int(p_li_origin integer, p_li_provider integer, p_li_receiver integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.droplisten_int(p_li_origin integer, p_li_provider integer, p_li_receiver integer) IS 'dropListen (li_origin, li_provider, li_receiver)

Process the DROP_LISTEN event, deleting the sl_listen entry for
the indicated (origin,provider,receiver) combination.';


--
-- Name: dropnode(integer[]); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.dropnode(p_no_ids integer[]) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	v_node_row		record;
	v_idx         integer;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Check that this got called on a different node
	-- ----
	if  "_primer_cluster2".getLocalNodeId('_primer_cluster2') = ANY (p_no_ids) then
		raise exception 'Slony-I: DROP_NODE cannot initiate on the dropped node';
	end if;

	--
	-- if any of the deleted nodes are receivers we drop the sl_subscribe line
	--
	delete from "_primer_cluster2".sl_subscribe where sub_receiver = ANY (p_no_ids);

	v_idx:=1;
	LOOP
	  EXIT WHEN v_idx>array_upper(p_no_ids,1) ;
	  select * into v_node_row from "_primer_cluster2".sl_node
			where no_id = p_no_ids[v_idx]
			for update;
	  if not found then
		 raise exception 'Slony-I: unknown node ID % %', p_no_ids[v_idx],v_idx;
	  end if;
	  -- ----
	  -- Make sure we do not break other nodes subscriptions with this
	  -- ----
	  if exists (select true from "_primer_cluster2".sl_subscribe
			where sub_provider = p_no_ids[v_idx])
	  then
		raise exception 'Slony-I: Node % is still configured as a data provider',
				p_no_ids[v_idx];
	  end if;

	  -- ----
	  -- Make sure no set originates there any more
	  -- ----
	  if exists (select true from "_primer_cluster2".sl_set
			where set_origin = p_no_ids[v_idx])
	  then
	  	  raise exception 'Slony-I: Node % is still origin of one or more sets',
				p_no_ids[v_idx];
	  end if;

	  -- ----
	  -- Call the internal drop functionality and generate the event
	  -- ----
	  perform "_primer_cluster2".dropNode_int(p_no_ids[v_idx]);
	  v_idx:=v_idx+1;
	END LOOP;
	return  "_primer_cluster2".createEvent('_primer_cluster2', 'DROP_NODE',
									array_to_string(p_no_ids,','));
end;
$$;


ALTER FUNCTION _primer_cluster2.dropnode(p_no_ids integer[]) OWNER TO postgres;

--
-- Name: FUNCTION dropnode(p_no_ids integer[]); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.dropnode(p_no_ids integer[]) IS 'generate DROP_NODE event to drop node node_id from replication';


--
-- Name: dropnode_int(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.dropnode_int(p_no_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_tab_row		record;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- If the dropped node is a remote node, clean the configuration
	-- from all traces for it.
	-- ----
	if p_no_id <> "_primer_cluster2".getLocalNodeId('_primer_cluster2') then
		delete from "_primer_cluster2".sl_subscribe
				where sub_receiver = p_no_id;
		delete from "_primer_cluster2".sl_listen
				where li_origin = p_no_id
					or li_provider = p_no_id
					or li_receiver = p_no_id;
		delete from "_primer_cluster2".sl_path
				where pa_server = p_no_id
					or pa_client = p_no_id;
		delete from "_primer_cluster2".sl_confirm
				where con_origin = p_no_id
					or con_received = p_no_id;
		delete from "_primer_cluster2".sl_event
				where ev_origin = p_no_id;
		delete from "_primer_cluster2".sl_node
				where no_id = p_no_id;

		return p_no_id;
	end if;

	-- ----
	-- This is us ... deactivate the node for now, the daemon
	-- will call uninstallNode() in a separate transaction.
	-- ----
	update "_primer_cluster2".sl_node
			set no_active = false
			where no_id = p_no_id;

	-- Rewrite sl_listen table
	perform "_primer_cluster2".RebuildListenEntries();

	return p_no_id;
end;
$$;


ALTER FUNCTION _primer_cluster2.dropnode_int(p_no_id integer) OWNER TO postgres;

--
-- Name: FUNCTION dropnode_int(p_no_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.dropnode_int(p_no_id integer) IS 'internal function to process DROP_NODE event to drop node node_id from replication';


--
-- Name: droppath(integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.droppath(p_pa_server integer, p_pa_client integer) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	v_row			record;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- There should be no existing subscriptions. Auto unsubscribing
	-- is considered too dangerous. 
	-- ----
	for v_row in select sub_set, sub_provider, sub_receiver
			from "_primer_cluster2".sl_subscribe
			where sub_provider = p_pa_server
			and sub_receiver = p_pa_client
	loop
		raise exception 
			'Slony-I: Path cannot be dropped, subscription of set % needs it',
			v_row.sub_set;
	end loop;

	-- ----
	-- Drop all sl_listen entries that depend on this path
	-- ----
	for v_row in select li_origin, li_provider, li_receiver
			from "_primer_cluster2".sl_listen
			where li_provider = p_pa_server
			and li_receiver = p_pa_client
	loop
		perform "_primer_cluster2".dropListen(
				v_row.li_origin, v_row.li_provider, v_row.li_receiver);
	end loop;

	-- ----
	-- Now drop the path and create the event
	-- ----
	perform "_primer_cluster2".dropPath_int(p_pa_server, p_pa_client);

	-- Rewrite sl_listen table
	perform "_primer_cluster2".RebuildListenEntries();

	return  "_primer_cluster2".createEvent ('_primer_cluster2', 'DROP_PATH',
			p_pa_server::text, p_pa_client::text);
end;
$$;


ALTER FUNCTION _primer_cluster2.droppath(p_pa_server integer, p_pa_client integer) OWNER TO postgres;

--
-- Name: FUNCTION droppath(p_pa_server integer, p_pa_client integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.droppath(p_pa_server integer, p_pa_client integer) IS 'Generate DROP_PATH event to drop path from pa_server to pa_client';


--
-- Name: droppath_int(integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.droppath_int(p_pa_server integer, p_pa_client integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Remove any dangling sl_listen entries with the server
	-- as provider and the client as receiver. This must have
	-- been cleared out before, but obviously was not.
	-- ----
	delete from "_primer_cluster2".sl_listen
			where li_provider = p_pa_server
			and li_receiver = p_pa_client;

	delete from "_primer_cluster2".sl_path
			where pa_server = p_pa_server
			and pa_client = p_pa_client;

	if found then
		-- Rewrite sl_listen table
		perform "_primer_cluster2".RebuildListenEntries();

		return 1;
	else
		-- Rewrite sl_listen table
		perform "_primer_cluster2".RebuildListenEntries();

		return 0;
	end if;
end;
$$;


ALTER FUNCTION _primer_cluster2.droppath_int(p_pa_server integer, p_pa_client integer) OWNER TO postgres;

--
-- Name: FUNCTION droppath_int(p_pa_server integer, p_pa_client integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.droppath_int(p_pa_server integer, p_pa_client integer) IS 'Process DROP_PATH event to drop path from pa_server to pa_client';


--
-- Name: dropset(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.dropset(p_set_id integer) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	v_origin			int4;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Check that the set exists and originates here
	-- ----
	select set_origin into v_origin from "_primer_cluster2".sl_set
			where set_id = p_set_id;
	if not found then
		raise exception 'Slony-I: set % not found', p_set_id;
	end if;
	if v_origin != "_primer_cluster2".getLocalNodeId('_primer_cluster2') then
		raise exception 'Slony-I: set % does not originate on local node',
				p_set_id;
	end if;

	-- ----
	-- Call the internal drop set functionality and generate the event
	-- ----
	perform "_primer_cluster2".dropSet_int(p_set_id);
	return  "_primer_cluster2".createEvent('_primer_cluster2', 'DROP_SET', 
			p_set_id::text);
end;
$$;


ALTER FUNCTION _primer_cluster2.dropset(p_set_id integer) OWNER TO postgres;

--
-- Name: FUNCTION dropset(p_set_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.dropset(p_set_id integer) IS 'Process DROP_SET event to drop replication of set set_id.  This involves:
- Removing log and deny access triggers
- Removing all traces of the set configuration, including sequences, tables, subscribers, syncs, and the set itself';


--
-- Name: dropset_int(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.dropset_int(p_set_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_tab_row			record;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Restore all tables original triggers and rules and remove
	-- our replication stuff.
	-- ----
	for v_tab_row in select tab_id from "_primer_cluster2".sl_table
			where tab_set = p_set_id
			order by tab_id
	loop
		perform "_primer_cluster2".alterTableDropTriggers(v_tab_row.tab_id);
	end loop;

	-- ----
	-- Remove all traces of the set configuration
	-- ----
	delete from "_primer_cluster2".sl_sequence
			where seq_set = p_set_id;
	delete from "_primer_cluster2".sl_table
			where tab_set = p_set_id;
	delete from "_primer_cluster2".sl_subscribe
			where sub_set = p_set_id;
	delete from "_primer_cluster2".sl_setsync
			where ssy_setid = p_set_id;
	delete from "_primer_cluster2".sl_set
			where set_id = p_set_id;

	-- Regenerate sl_listen since we revised the subscriptions
	perform "_primer_cluster2".RebuildListenEntries();

	-- Run addPartialLogIndices() to try to add indices to unused sl_log_? table
	perform "_primer_cluster2".addPartialLogIndices();

	return p_set_id;
end;
$$;


ALTER FUNCTION _primer_cluster2.dropset_int(p_set_id integer) OWNER TO postgres;

--
-- Name: enable_indexes_on_table(oid); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.enable_indexes_on_table(i_oid oid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
	update pg_catalog.pg_class set relhasindex ='t' where oid = i_oid;
	return 1;
end $$;


ALTER FUNCTION _primer_cluster2.enable_indexes_on_table(i_oid oid) OWNER TO postgres;

--
-- Name: FUNCTION enable_indexes_on_table(i_oid oid); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.enable_indexes_on_table(i_oid oid) IS 're-enable indexes on the specified table.

This may be set as a SECURITY DEFINER in order to eliminate the need
for superuser access by Slony-I.
';


--
-- Name: enablenode(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.enablenode(p_no_id integer) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	v_local_node_id	int4;
	v_node_row		record;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Check that we are the node to activate and that we are
	-- currently disabled.
	-- ----
	v_local_node_id := "_primer_cluster2".getLocalNodeId('_primer_cluster2');
	select * into v_node_row
			from "_primer_cluster2".sl_node
			where no_id = p_no_id
			for update;
	if not found then 
		raise exception 'Slony-I: node % not found', p_no_id;
	end if;
	if v_node_row.no_active then
		raise exception 'Slony-I: node % is already active', p_no_id;
	end if;

	-- ----
	-- Activate this node and generate the ENABLE_NODE event
	-- ----
	perform "_primer_cluster2".enableNode_int (p_no_id);
	return  "_primer_cluster2".createEvent('_primer_cluster2', 'ENABLE_NODE',
									p_no_id::text);
end;
$$;


ALTER FUNCTION _primer_cluster2.enablenode(p_no_id integer) OWNER TO postgres;

--
-- Name: FUNCTION enablenode(p_no_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.enablenode(p_no_id integer) IS 'no_id - Node ID #

Generate the ENABLE_NODE event for node no_id';


--
-- Name: enablenode_int(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.enablenode_int(p_no_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_local_node_id	int4;
	v_node_row		record;
	v_sub_row		record;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Check that the node is inactive
	-- ----
	select * into v_node_row
			from "_primer_cluster2".sl_node
			where no_id = p_no_id
			for update;
	if not found then 
		raise exception 'Slony-I: node % not found', p_no_id;
	end if;
	if v_node_row.no_active then
		return p_no_id;
	end if;

	-- ----
	-- Activate the node and generate sl_confirm status rows for it.
	-- ----
	update "_primer_cluster2".sl_node
			set no_active = 't'
			where no_id = p_no_id;
	insert into "_primer_cluster2".sl_confirm
			(con_origin, con_received, con_seqno)
			select no_id, p_no_id, 0 from "_primer_cluster2".sl_node
				where no_id != p_no_id
				and no_active;
	insert into "_primer_cluster2".sl_confirm
			(con_origin, con_received, con_seqno)
			select p_no_id, no_id, 0 from "_primer_cluster2".sl_node
				where no_id != p_no_id
				and no_active;

	-- ----
	-- Generate ENABLE_SUBSCRIPTION events for all sets that
	-- origin here and are subscribed by the just enabled node.
	-- ----
	v_local_node_id := "_primer_cluster2".getLocalNodeId('_primer_cluster2');
	for v_sub_row in select SUB.sub_set, SUB.sub_provider from
			"_primer_cluster2".sl_set S,
			"_primer_cluster2".sl_subscribe SUB
			where S.set_origin = v_local_node_id
			and S.set_id = SUB.sub_set
			and SUB.sub_receiver = p_no_id
			for update of S
	loop
		perform "_primer_cluster2".enableSubscription (v_sub_row.sub_set,
				v_sub_row.sub_provider, p_no_id);
	end loop;

	return p_no_id;
end;
$$;


ALTER FUNCTION _primer_cluster2.enablenode_int(p_no_id integer) OWNER TO postgres;

--
-- Name: FUNCTION enablenode_int(p_no_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.enablenode_int(p_no_id integer) IS 'no_id - Node ID #

Internal function to process the ENABLE_NODE event for node no_id';


--
-- Name: enablesubscription(integer, integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.enablesubscription(p_sub_set integer, p_sub_provider integer, p_sub_receiver integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
	return  "_primer_cluster2".enableSubscription_int (p_sub_set, 
			p_sub_provider, p_sub_receiver);
end;
$$;


ALTER FUNCTION _primer_cluster2.enablesubscription(p_sub_set integer, p_sub_provider integer, p_sub_receiver integer) OWNER TO postgres;

--
-- Name: FUNCTION enablesubscription(p_sub_set integer, p_sub_provider integer, p_sub_receiver integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.enablesubscription(p_sub_set integer, p_sub_provider integer, p_sub_receiver integer) IS 'enableSubscription (sub_set, sub_provider, sub_receiver)

Indicates that sub_receiver intends subscribing to set sub_set from
sub_provider.  Work is all done by the internal function
enableSubscription_int (sub_set, sub_provider, sub_receiver).';


--
-- Name: enablesubscription_int(integer, integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.enablesubscription_int(p_sub_set integer, p_sub_provider integer, p_sub_receiver integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_n					int4;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- The real work is done in the replication engine. All
	-- we have to do here is remembering that it happened.
	-- ----

	-- ----
	-- Well, not only ... we might be missing an important event here
	-- ----
	if not exists (select true from "_primer_cluster2".sl_path
			where pa_server = p_sub_provider
			and pa_client = p_sub_receiver)
	then
		insert into "_primer_cluster2".sl_path
				(pa_server, pa_client, pa_conninfo, pa_connretry)
				values 
				(p_sub_provider, p_sub_receiver, 
				'<event pending>', 10);
	end if;

	update "_primer_cluster2".sl_subscribe
			set sub_active = 't'
			where sub_set = p_sub_set
			and sub_receiver = p_sub_receiver;
	get diagnostics v_n = row_count;
	if v_n = 0 then
		insert into "_primer_cluster2".sl_subscribe
				(sub_set, sub_provider, sub_receiver,
				sub_forward, sub_active)
				values
				(p_sub_set, p_sub_provider, p_sub_receiver,
				false, true);
	end if;

	-- Rewrite sl_listen table
	perform "_primer_cluster2".RebuildListenEntries();

	return p_sub_set;
end;
$$;


ALTER FUNCTION _primer_cluster2.enablesubscription_int(p_sub_set integer, p_sub_provider integer, p_sub_receiver integer) OWNER TO postgres;

--
-- Name: FUNCTION enablesubscription_int(p_sub_set integer, p_sub_provider integer, p_sub_receiver integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.enablesubscription_int(p_sub_set integer, p_sub_provider integer, p_sub_receiver integer) IS 'enableSubscription_int (sub_set, sub_provider, sub_receiver)

Internal function to enable subscription of node sub_receiver to set
sub_set via node sub_provider.

slon does most of the work; all we need do here is to remember that it
happened.  The function updates sl_subscribe, indicating that the
subscription has become active.';


--
-- Name: failednode(integer, integer, integer[]); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.failednode(p_failed_node integer, p_backup_node integer, p_failed_nodes integer[]) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_row				record;
	v_row2				record;
	v_failed					boolean;
    v_restart_required          boolean;
begin
	
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	v_restart_required:=false;
	--
	-- any nodes other than the backup receiving
	-- ANY subscription from a failed node
	-- will now get that data from the backup node.
	update "_primer_cluster2".sl_subscribe set 
		   sub_provider=p_backup_node
		   where sub_provider=p_failed_node
		   and sub_receiver<>p_backup_node
		   and sub_receiver <> ALL (p_failed_nodes);
	if found then
	   v_restart_required:=true;
	end if;
	-- 
	-- if this node is receiving a subscription from the backup node
	-- with a failed node as the provider we need to fix this.
	update "_primer_cluster2".sl_subscribe set 
	        sub_provider=p_backup_node
		from "_primer_cluster2".sl_set
		where set_id = sub_set
		and set_origin=p_failed_node
		and sub_provider = ANY(p_failed_nodes)
		and sub_receiver="_primer_cluster2".getLocalNodeId('_primer_cluster2');

	-- ----
	-- Terminate all connections of the failed node the hard way
	-- ----
	perform "_primer_cluster2".terminateNodeConnections(p_failed_node);

	-- Clear out the paths for the failed node.
	-- This ensures that *this* node won't be pulling data from
	-- the failed node even if it *does* become accessible

	update "_primer_cluster2".sl_path set pa_conninfo='<event pending>' WHERE
	   		  pa_server=p_failed_node
			  and pa_conninfo<>'<event pending>';

	if found then
	   v_restart_required:=true;
	end if;

	v_failed := exists (select 1 from "_primer_cluster2".sl_node 
		   where no_failed=true and no_id=p_failed_node);

    if not v_failed then
	   	
		update "_primer_cluster2".sl_node set no_failed=true where no_id = ANY (p_failed_nodes)
			   and no_failed=false;
		if found then
	   	   v_restart_required:=true;
		end if;
	end if;	

	if v_restart_required then
	  -- Rewrite sl_listen table
	  perform "_primer_cluster2".RebuildListenEntries();	   
	
	  -- ----
	  -- Make sure the node daemon will restart
 	  -- ----
	  notify "_primer_cluster2_Restart";
    end if;


	-- ----
	-- That is it - so far.
	-- ----
	return p_failed_node;
end;
$$;


ALTER FUNCTION _primer_cluster2.failednode(p_failed_node integer, p_backup_node integer, p_failed_nodes integer[]) OWNER TO postgres;

--
-- Name: FUNCTION failednode(p_failed_node integer, p_backup_node integer, p_failed_nodes integer[]); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.failednode(p_failed_node integer, p_backup_node integer, p_failed_nodes integer[]) IS 'Initiate failover from failed_node to backup_node.  This function must be called on all nodes, 
and then waited for the restart of all node daemons.';


--
-- Name: failednode2(integer, integer, bigint, integer[]); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.failednode2(p_failed_node integer, p_backup_node integer, p_ev_seqno bigint, p_failed_nodes integer[]) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	v_row				record;
	v_new_event			bigint;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	select * into v_row
			from "_primer_cluster2".sl_event
			where ev_origin = p_failed_node
			and ev_seqno = p_ev_seqno;
	if not found then
		raise exception 'Slony-I: event %,% not found',
				p_failed_node, p_ev_seqno;
	end if;

	update "_primer_cluster2".sl_node set no_failed=true  where no_id = ANY 
	(p_failed_nodes) and no_failed=false;
	-- Rewrite sl_listen table
	perform "_primer_cluster2".RebuildListenEntries();
	-- ----
	-- Make sure the node daemon will restart
	-- ----
	raise notice 'calling restart node %',p_failed_node;

	notify "_primer_cluster2_Restart";

	select "_primer_cluster2".createEvent('_primer_cluster2','FAILOVER_NODE',
								p_failed_node::text,p_ev_seqno::text,
								array_to_string(p_failed_nodes,','))
			into v_new_event;
		

	return v_new_event;
end;
$$;


ALTER FUNCTION _primer_cluster2.failednode2(p_failed_node integer, p_backup_node integer, p_ev_seqno bigint, p_failed_nodes integer[]) OWNER TO postgres;

--
-- Name: FUNCTION failednode2(p_failed_node integer, p_backup_node integer, p_ev_seqno bigint, p_failed_nodes integer[]); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.failednode2(p_failed_node integer, p_backup_node integer, p_ev_seqno bigint, p_failed_nodes integer[]) IS 'FUNCTION failedNode2 (failed_node, backup_node, set_id, ev_seqno, ev_seqfake,p_failed_nodes)

On the node that has the highest sequence number of the failed node,
fake the FAILOVER_SET event.';


--
-- Name: failednode3(integer, integer, bigint); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.failednode3(p_failed_node integer, p_backup_node integer, p_seq_no bigint) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare

begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	perform "_primer_cluster2".failoverSet_int(p_failed_node,
		p_backup_node,p_seq_no);

	notify "_primer_cluster2_Restart";
    return 0;
end;
$$;


ALTER FUNCTION _primer_cluster2.failednode3(p_failed_node integer, p_backup_node integer, p_seq_no bigint) OWNER TO postgres;

--
-- Name: failoverset_int(integer, integer, bigint); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.failoverset_int(p_failed_node integer, p_backup_node integer, p_last_seqno bigint) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_row				record;
	v_last_sync			int8;
	v_set				int4;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	SELECT max(ev_seqno) into v_last_sync FROM "_primer_cluster2".sl_event where
		   ev_origin=p_failed_node;
	if v_last_sync > p_last_seqno then
	   -- this node is ahead of the last sequence number from the
	   -- failed node that the backup node has.
	   -- this node must unsubscribe from all sets from the origin.
	   for v_set in select set_id from "_primer_cluster2".sl_set where 
		set_origin=p_failed_node
		loop
			raise warning 'Slony is dropping the subscription of set % found sync %s bigger than %s '
			, v_set, v_last_sync::text, p_last_seqno::text;
			perform "_primer_cluster2".unsubscribeSet(v_set,
				   "_primer_cluster2".getLocalNodeId('_primer_cluster2'),
				   true);
		end loop;
		delete from "_primer_cluster2".sl_event where ev_origin=p_failed_node
			   and ev_seqno > p_last_seqno;
	end if;
	-- ----
	-- Change the origin of the set now to the backup node.
	-- On the backup node this includes changing all the
	-- trigger and protection stuff
	for v_set in select set_id from "_primer_cluster2".sl_set where 
		set_origin=p_failed_node
	loop
	-- ----
	   if p_backup_node = "_primer_cluster2".getLocalNodeId('_primer_cluster2') then
	   	  	delete from "_primer_cluster2".sl_setsync
				where ssy_setid = v_set;
			delete from "_primer_cluster2".sl_subscribe
				where sub_set = v_set
					and sub_receiver = p_backup_node;
			update "_primer_cluster2".sl_set
				set set_origin = p_backup_node
				where set_id = v_set;		
			 update "_primer_cluster2".sl_subscribe
						set sub_provider=p_backup_node
					  	FROM "_primer_cluster2".sl_node receive_node
					   where sub_set = v_set
					   and sub_provider=p_failed_node
					   and sub_receiver=receive_node.no_id
					   and receive_node.no_failed=false;			

			for v_row in select * from "_primer_cluster2".sl_table
				where tab_set = v_set
				order by tab_id
			loop
				perform "_primer_cluster2".alterTableConfigureTriggers(v_row.tab_id);
			end loop;
	else
		raise notice 'deleting from sl_subscribe all rows with receiver %',
		p_backup_node;
		
			delete from "_primer_cluster2".sl_subscribe
					  where sub_set = v_set
					  and sub_receiver = p_backup_node;
		
			update "_primer_cluster2".sl_subscribe
				 		set sub_provider=p_backup_node
						FROM "_primer_cluster2".sl_node receive_node
					   where sub_set = v_set
					    and sub_provider=p_failed_node
						 and sub_provider=p_failed_node
					   and sub_receiver=receive_node.no_id
					   and receive_node.no_failed=false;
			update "_primer_cluster2".sl_set
					   set set_origin = p_backup_node
				where set_id = v_set;
			-- ----
			-- If we are a subscriber of the set ourself, change our
			-- setsync status to reflect the new set origin.
			-- ----
			if exists (select true from "_primer_cluster2".sl_subscribe
			   where sub_set = v_set
			   	and sub_receiver = "_primer_cluster2".getLocalNodeId(
						'_primer_cluster2'))
			then
				delete from "_primer_cluster2".sl_setsync
					   where ssy_setid = v_set;

				select coalesce(max(ev_seqno), 0) into v_last_sync
					   from "_primer_cluster2".sl_event
					   where ev_origin = p_backup_node
					   and ev_type = 'SYNC';
				if v_last_sync > 0 then
				   insert into "_primer_cluster2".sl_setsync
					(ssy_setid, ssy_origin, ssy_seqno,
					ssy_snapshot, ssy_action_list)
					select v_set, p_backup_node, v_last_sync,
					ev_snapshot, NULL
					from "_primer_cluster2".sl_event
					where ev_origin = p_backup_node
						and ev_seqno = v_last_sync;
				else
					insert into "_primer_cluster2".sl_setsync
					(ssy_setid, ssy_origin, ssy_seqno,
					ssy_snapshot, ssy_action_list)
					values (v_set, p_backup_node, '0',
					'1:1:', NULL);
				end if;	
			end if;
		end if;
	end loop;
	
	--If there are any subscriptions with 
	--the failed_node being the provider then
	--we want to redirect those subscriptions
	--to come from the backup node.
	--
	-- The backup node should be a valid
	-- provider for all subscriptions served
	-- by the failed node. (otherwise it
	-- wouldn't be a allowable backup node).
--	delete from "_primer_cluster2".sl_subscribe
--		   where sub_receiver=p_backup_node;
		   
	update "_primer_cluster2".sl_subscribe	       
	       set sub_provider=p_backup_node
	       from "_primer_cluster2".sl_node
	       where sub_provider=p_failed_node
	       and sl_node.no_id=sub_receiver
	       and sl_node.no_failed=false
		   and sub_receiver<>p_backup_node;
		   
	update "_primer_cluster2".sl_subscribe	       
	       set sub_provider=(select set_origin from
		   	   "_primer_cluster2".sl_set where set_id=
			   sub_set)
			where sub_provider=p_failed_node
			and sub_receiver=p_backup_node;
		   
	update "_primer_cluster2".sl_node
		   set no_active=false WHERE 
		   no_id=p_failed_node;

	-- Rewrite sl_listen table
	perform "_primer_cluster2".RebuildListenEntries();


	return p_failed_node;
end;
$$;


ALTER FUNCTION _primer_cluster2.failoverset_int(p_failed_node integer, p_backup_node integer, p_last_seqno bigint) OWNER TO postgres;

--
-- Name: FUNCTION failoverset_int(p_failed_node integer, p_backup_node integer, p_last_seqno bigint); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.failoverset_int(p_failed_node integer, p_backup_node integer, p_last_seqno bigint) IS 'FUNCTION failoverSet_int (failed_node, backup_node, set_id, wait_seqno)

Finish failover for one set.';


--
-- Name: finishtableaftercopy(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.finishtableaftercopy(p_tab_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_tab_oid		oid;
	v_tab_fqname	text;
begin
	-- ----
	-- Get the tables OID and fully qualified name
	-- ---
	select	PGC.oid,
			"_primer_cluster2".slon_quote_brute(PGN.nspname) || '.' ||
			"_primer_cluster2".slon_quote_brute(PGC.relname) as tab_fqname
		into v_tab_oid, v_tab_fqname
			from "_primer_cluster2".sl_table T,   
				"pg_catalog".pg_class PGC, "pg_catalog".pg_namespace PGN
				where T.tab_id = p_tab_id
				and T.tab_reloid = PGC.oid
				and PGC.relnamespace = PGN.oid;
	if not found then
		raise exception 'Table with ID % not found in sl_table', p_tab_id;
	end if;

	-- ----
	-- Reenable indexes and reindex the table.
	-- ----
	perform "_primer_cluster2".enable_indexes_on_table(v_tab_oid);
	execute 'reindex table ' || "_primer_cluster2".slon_quote_input(v_tab_fqname);

	return 1;
end;
$$;


ALTER FUNCTION _primer_cluster2.finishtableaftercopy(p_tab_id integer) OWNER TO postgres;

--
-- Name: FUNCTION finishtableaftercopy(p_tab_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.finishtableaftercopy(p_tab_id integer) IS 'Reenable index maintenance and reindex the table';


--
-- Name: forwardconfirm(integer, integer, bigint, timestamp without time zone); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.forwardconfirm(p_con_origin integer, p_con_received integer, p_con_seqno bigint, p_con_timestamp timestamp without time zone) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	v_max_seqno		bigint;
begin
	select into v_max_seqno coalesce(max(con_seqno), 0)
			from "_primer_cluster2".sl_confirm
			where con_origin = p_con_origin
			and con_received = p_con_received;
	if v_max_seqno < p_con_seqno then
		insert into "_primer_cluster2".sl_confirm 
				(con_origin, con_received, con_seqno, con_timestamp)
				values (p_con_origin, p_con_received, p_con_seqno,
					p_con_timestamp);
		v_max_seqno = p_con_seqno;
	end if;

	return v_max_seqno;
end;
$$;


ALTER FUNCTION _primer_cluster2.forwardconfirm(p_con_origin integer, p_con_received integer, p_con_seqno bigint, p_con_timestamp timestamp without time zone) OWNER TO postgres;

--
-- Name: FUNCTION forwardconfirm(p_con_origin integer, p_con_received integer, p_con_seqno bigint, p_con_timestamp timestamp without time zone); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.forwardconfirm(p_con_origin integer, p_con_received integer, p_con_seqno bigint, p_con_timestamp timestamp without time zone) IS 'forwardConfirm (p_con_origin, p_con_received, p_con_seqno, p_con_timestamp)

Confirms (recorded in sl_confirm) that items from p_con_origin up to
p_con_seqno have been received by node p_con_received as of
p_con_timestamp, and raises an event to forward this confirmation.';


--
-- Name: generate_sync_event(interval); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.generate_sync_event(p_interval interval) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_node_row     record;

BEGIN
	select 1 into v_node_row from "_primer_cluster2".sl_event 
       	  where ev_type = 'SYNC' and ev_origin = "_primer_cluster2".getLocalNodeId('_primer_cluster2')
          and ev_timestamp > now() - p_interval limit 1;
	if not found then
		-- If there has been no SYNC in the last interval, then push one
		perform "_primer_cluster2".createEvent('_primer_cluster2', 'SYNC', NULL);
		return 1;
	else
		return 0;
	end if;
end;
$$;


ALTER FUNCTION _primer_cluster2.generate_sync_event(p_interval interval) OWNER TO postgres;

--
-- Name: FUNCTION generate_sync_event(p_interval interval); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.generate_sync_event(p_interval interval) IS 'Generate a sync event if there has not been one in the requested interval, and this is a provider node.';


--
-- Name: getlocalnodeid(name); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.getlocalnodeid(p_cluster name) RETURNS integer
    LANGUAGE c SECURITY DEFINER
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_getLocalNodeId';


ALTER FUNCTION _primer_cluster2.getlocalnodeid(p_cluster name) OWNER TO postgres;

--
-- Name: FUNCTION getlocalnodeid(p_cluster name); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.getlocalnodeid(p_cluster name) IS 'Returns the node ID of the node being serviced on the local database';


--
-- Name: getmoduleversion(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.getmoduleversion() RETURNS text
    LANGUAGE c SECURITY DEFINER
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_getModuleVersion';


ALTER FUNCTION _primer_cluster2.getmoduleversion() OWNER TO postgres;

--
-- Name: FUNCTION getmoduleversion(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.getmoduleversion() IS 'Returns the compiled-in version number of the Slony-I shared object';


--
-- Name: initializelocalnode(integer, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.initializelocalnode(p_local_node_id integer, p_comment text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_old_node_id		int4;
	v_first_log_no		int4;
	v_event_seq			int8;
begin
	-- ----
	-- Make sure this node is uninitialized or got reset
	-- ----
	select last_value::int4 into v_old_node_id from "_primer_cluster2".sl_local_node_id;
	if v_old_node_id != -1 then
		raise exception 'Slony-I: This node is already initialized';
	end if;

	-- ----
	-- Set sl_local_node_id to the requested value and add our
	-- own system to sl_node.
	-- ----
	perform setval('"_primer_cluster2".sl_local_node_id', p_local_node_id);
	perform "_primer_cluster2".storeNode_int (p_local_node_id, p_comment);

	if (pg_catalog.current_setting('max_identifier_length')::integer - pg_catalog.length('"_primer_cluster2"')) < 5 then
		raise notice 'Slony-I: Cluster name length [%] versus system max_identifier_length [%] ', pg_catalog.length('"_primer_cluster2"'), pg_catalog.current_setting('max_identifier_length');
		raise notice 'leaves narrow/no room for some Slony-I-generated objects (such as indexes).';
		raise notice 'You may run into problems later!';
	end if;
	
	--
	-- Put the apply trigger onto sl_log_1 and sl_log_2
	--
	create trigger apply_trigger
		before INSERT on "_primer_cluster2".sl_log_1
		for each row execute procedure "_primer_cluster2".logApply('_primer_cluster2');
	alter table "_primer_cluster2".sl_log_1
	  enable replica trigger apply_trigger;
	create trigger apply_trigger
		before INSERT on "_primer_cluster2".sl_log_2
		for each row execute procedure "_primer_cluster2".logApply('_primer_cluster2');
	alter table "_primer_cluster2".sl_log_2
			enable replica trigger apply_trigger;

	return p_local_node_id;
end;
$$;


ALTER FUNCTION _primer_cluster2.initializelocalnode(p_local_node_id integer, p_comment text) OWNER TO postgres;

--
-- Name: FUNCTION initializelocalnode(p_local_node_id integer, p_comment text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.initializelocalnode(p_local_node_id integer, p_comment text) IS 'no_id - Node ID #
no_comment - Human-oriented comment

Initializes the new node, no_id';


--
-- Name: is_node_reachable(integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.is_node_reachable(origin_node_id integer, receiver_node_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
declare
		listen_row record;
		reachable boolean;
begin
	reachable:=false;
	select * into listen_row from "_primer_cluster2".sl_listen where
		   li_origin=origin_node_id and li_receiver=receiver_node_id;
	if found then
	   reachable:=true;
	end if;
  return reachable;
end $$;


ALTER FUNCTION _primer_cluster2.is_node_reachable(origin_node_id integer, receiver_node_id integer) OWNER TO postgres;

--
-- Name: FUNCTION is_node_reachable(origin_node_id integer, receiver_node_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.is_node_reachable(origin_node_id integer, receiver_node_id integer) IS 'Is the receiver node reachable from the origin, via any of the listen paths?';


--
-- Name: issubscriptioninprogress(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.issubscriptioninprogress(p_add_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
begin
	if exists (select true from "_primer_cluster2".sl_event
			where ev_type = 'ENABLE_SUBSCRIPTION'
			and ev_data1 = p_add_id::text
			and ev_seqno > (select max(con_seqno) from "_primer_cluster2".sl_confirm
					where con_origin = ev_origin
					and con_received::text = ev_data3))
	then
		return true;
	else
		return false;
	end if;
end;
$$;


ALTER FUNCTION _primer_cluster2.issubscriptioninprogress(p_add_id integer) OWNER TO postgres;

--
-- Name: FUNCTION issubscriptioninprogress(p_add_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.issubscriptioninprogress(p_add_id integer) IS 'Checks to see if a subscription for the indicated set is in progress.
Returns true if a subscription is in progress. Otherwise false';


--
-- Name: killbackend(integer, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.killbackend(p_pid integer, p_signame text) RETURNS integer
    LANGUAGE c
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_killBackend';


ALTER FUNCTION _primer_cluster2.killbackend(p_pid integer, p_signame text) OWNER TO postgres;

--
-- Name: FUNCTION killbackend(p_pid integer, p_signame text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.killbackend(p_pid integer, p_signame text) IS 'Send a signal to a postgres process. Requires superuser rights';


--
-- Name: lockedset(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.lockedset() RETURNS trigger
    LANGUAGE c
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_lockedSet';


ALTER FUNCTION _primer_cluster2.lockedset() OWNER TO postgres;

--
-- Name: FUNCTION lockedset(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.lockedset() IS 'Trigger function to prevent modifications to a table before and after a moveSet()';


--
-- Name: lockset(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.lockset(p_set_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_local_node_id		int4;
	v_set_row			record;
	v_tab_row			record;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Check that the set exists and that we are the origin
	-- and that it is not already locked.
	-- ----
	v_local_node_id := "_primer_cluster2".getLocalNodeId('_primer_cluster2');
	select * into v_set_row from "_primer_cluster2".sl_set
			where set_id = p_set_id
			for update;
	if not found then
		raise exception 'Slony-I: set % not found', p_set_id;
	end if;
	if v_set_row.set_origin <> v_local_node_id then
		raise exception 'Slony-I: set % does not originate on local node',
				p_set_id;
	end if;
	if v_set_row.set_locked notnull then
		raise exception 'Slony-I: set % is already locked', p_set_id;
	end if;

	-- ----
	-- Place the lockedSet trigger on all tables in the set.
	-- ----
	for v_tab_row in select T.tab_id,
			"_primer_cluster2".slon_quote_brute(PGN.nspname) || '.' ||
			"_primer_cluster2".slon_quote_brute(PGC.relname) as tab_fqname
			from "_primer_cluster2".sl_table T,
				"pg_catalog".pg_class PGC, "pg_catalog".pg_namespace PGN
			where T.tab_set = p_set_id
				and T.tab_reloid = PGC.oid
				and PGC.relnamespace = PGN.oid
			order by tab_id
	loop
		execute 'create trigger "_primer_cluster2_lockedset" ' || 
				'before insert or update or delete on ' ||
				v_tab_row.tab_fqname || ' for each row execute procedure
				"_primer_cluster2".lockedSet (''_primer_cluster2'');';
	end loop;

	-- ----
	-- Remember our snapshots xmax as for the set locking
	-- ----
	update "_primer_cluster2".sl_set
			set set_locked = "pg_catalog".txid_snapshot_xmax("pg_catalog".txid_current_snapshot())
			where set_id = p_set_id;

	return p_set_id;
end;
$$;


ALTER FUNCTION _primer_cluster2.lockset(p_set_id integer) OWNER TO postgres;

--
-- Name: FUNCTION lockset(p_set_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.lockset(p_set_id integer) IS 'lockSet(set_id)

Add a special trigger to all tables of a set that disables access to
it.';


--
-- Name: log_truncate(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.log_truncate() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
	declare
		r_role text;
		c_nspname text;
		c_relname text;
		c_log integer;
		c_node integer;
		c_tabid integer;
	begin
		-- Ignore this call if session_replication_role = 'local'
		select into r_role setting
			from pg_catalog.pg_settings where name = 'session_replication_role';
		if r_role = 'local' then
			return NULL;
		end if;

        c_tabid := tg_argv[0];
	    c_node := "_primer_cluster2".getLocalNodeId('_primer_cluster2');
		select tab_nspname, tab_relname into c_nspname, c_relname
				  from "_primer_cluster2".sl_table where tab_id = c_tabid;
		select last_value into c_log from "_primer_cluster2".sl_log_status;
		if c_log in (0, 2) then
			insert into "_primer_cluster2".sl_log_1 (
					log_origin, log_txid, log_tableid, 
					log_actionseq, log_tablenspname, 
					log_tablerelname, log_cmdtype, 
					log_cmdupdncols, log_cmdargs
				) values (
					c_node, pg_catalog.txid_current(), c_tabid,
					nextval('"_primer_cluster2".sl_action_seq'), c_nspname,
					c_relname, 'T', 0, '{}'::text[]);
		else   -- (1, 3) 
			insert into "_primer_cluster2".sl_log_2 (
					log_origin, log_txid, log_tableid, 
					log_actionseq, log_tablenspname, 
					log_tablerelname, log_cmdtype, 
					log_cmdupdncols, log_cmdargs
				) values (
					c_node, pg_catalog.txid_current(), c_tabid,
					nextval('"_primer_cluster2".sl_action_seq'), c_nspname,
					c_relname, 'T', 0, '{}'::text[]);
		end if;
		return NULL;
    end
$$;


ALTER FUNCTION _primer_cluster2.log_truncate() OWNER TO postgres;

--
-- Name: FUNCTION log_truncate(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.log_truncate() IS 'trigger function run when a replicated table receives a TRUNCATE request';


--
-- Name: logapply(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.logapply() RETURNS trigger
    LANGUAGE c SECURITY DEFINER
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_logApply';


ALTER FUNCTION _primer_cluster2.logapply() OWNER TO postgres;

--
-- Name: logapplysavestats(name, integer, interval); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.logapplysavestats(p_cluster name, p_origin integer, p_duration interval) RETURNS integer
    LANGUAGE c
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_logApplySaveStats';


ALTER FUNCTION _primer_cluster2.logapplysavestats(p_cluster name, p_origin integer, p_duration interval) OWNER TO postgres;

--
-- Name: logapplysetcachesize(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.logapplysetcachesize(p_size integer) RETURNS integer
    LANGUAGE c
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_logApplySetCacheSize';


ALTER FUNCTION _primer_cluster2.logapplysetcachesize(p_size integer) OWNER TO postgres;

--
-- Name: logswitch_finish(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.logswitch_finish() RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_current_status	int4;
	v_dummy				record;
	v_origin	int8;
	v_seqno		int8;
	v_xmin		bigint;
	v_purgeable boolean;
BEGIN
	-- ----
	-- Get the current log status.
	-- ----
	select last_value into v_current_status from "_primer_cluster2".sl_log_status;

	-- ----
	-- status value 0 or 1 means that there is no log switch in progress
	-- ----
	if v_current_status = 0 or v_current_status = 1 then
		return 0;
	end if;

	-- ----
	-- status = 2: sl_log_1 active, cleanup sl_log_2
	-- ----
	if v_current_status = 2 then
		v_purgeable := 'true';
		
		-- ----
		-- Attempt to lock sl_log_2 in order to make sure there are no other transactions 
		-- currently writing to it. Exit if it is still in use. This prevents TRUNCATE from 
		-- blocking writers to sl_log_2 while it is waiting for a lock. It also prevents it 
		-- immediately truncating log data generated inside the transaction which was active 
		-- when logswitch_finish() was called (and was blocking TRUNCATE) as soon as that 
		-- transaction is committed.
		-- ----
		begin
			lock table "_primer_cluster2".sl_log_2 in access exclusive mode nowait;
		exception when lock_not_available then
			raise notice 'Slony-I: could not lock sl_log_2 - sl_log_2 not truncated';
			return -1;
		end;

		-- ----
		-- The cleanup thread calls us after it did the delete and
		-- vacuum of both log tables. If sl_log_2 is empty now, we
		-- can truncate it and the log switch is done.
		-- ----
	        for v_origin, v_seqno, v_xmin in
		  select ev_origin, ev_seqno, "pg_catalog".txid_snapshot_xmin(ev_snapshot) from "_primer_cluster2".sl_event
	          where (ev_origin, ev_seqno) in (select ev_origin, min(ev_seqno) from "_primer_cluster2".sl_event where ev_type = 'SYNC' group by ev_origin)
		loop
			if exists (select 1 from "_primer_cluster2".sl_log_2 where log_origin = v_origin and log_txid >= v_xmin limit 1) then
				v_purgeable := 'false';
			end if;
	        end loop;
		if not v_purgeable then
			-- ----
			-- Found a row ... log switch is still in progress.
			-- ----
			raise notice 'Slony-I: log switch to sl_log_1 still in progress - sl_log_2 not truncated';
			return -1;
		end if;

		raise notice 'Slony-I: log switch to sl_log_1 complete - truncate sl_log_2';
		truncate "_primer_cluster2".sl_log_2;
		if exists (select * from "pg_catalog".pg_class c, "pg_catalog".pg_namespace n, "pg_catalog".pg_attribute a where c.relname = 'sl_log_2' and n.oid = c.relnamespace and a.attrelid = c.oid and a.attname = 'oid') then
	                execute 'alter table "_primer_cluster2".sl_log_2 set without oids;';
		end if;		
		perform "pg_catalog".setval('"_primer_cluster2".sl_log_status', 0);
		-- Run addPartialLogIndices() to try to add indices to unused sl_log_? table
		perform "_primer_cluster2".addPartialLogIndices();

		return 1;
	end if;

	-- ----
	-- status = 3: sl_log_2 active, cleanup sl_log_1
	-- ----
	if v_current_status = 3 then
		v_purgeable := 'true';

		-- ----
		-- Attempt to lock sl_log_1 in order to make sure there are no other transactions 
		-- currently writing to it. Exit if it is still in use. This prevents TRUNCATE from 
		-- blocking writes to sl_log_1 while it is waiting for a lock. It also prevents it 
		-- immediately truncating log data generated inside the transaction which was active 
		-- when logswitch_finish() was called (and was blocking TRUNCATE) as soon as that 
		-- transaction is committed.
		-- ----
		begin
			lock table "_primer_cluster2".sl_log_1 in access exclusive mode nowait;
		exception when lock_not_available then
			raise notice 'Slony-I: could not lock sl_log_1 - sl_log_1 not truncated';
			return -1;
		end;

		-- ----
		-- The cleanup thread calls us after it did the delete and
		-- vacuum of both log tables. If sl_log_2 is empty now, we
		-- can truncate it and the log switch is done.
		-- ----
	        for v_origin, v_seqno, v_xmin in
		  select ev_origin, ev_seqno, "pg_catalog".txid_snapshot_xmin(ev_snapshot) from "_primer_cluster2".sl_event
	          where (ev_origin, ev_seqno) in (select ev_origin, min(ev_seqno) from "_primer_cluster2".sl_event where ev_type = 'SYNC' group by ev_origin)
		loop
			if (exists (select 1 from "_primer_cluster2".sl_log_1 where log_origin = v_origin and log_txid >= v_xmin limit 1)) then
				v_purgeable := 'false';
			end if;
	        end loop;
		if not v_purgeable then
			-- ----
			-- Found a row ... log switch is still in progress.
			-- ----
			raise notice 'Slony-I: log switch to sl_log_2 still in progress - sl_log_1 not truncated';
			return -1;
		end if;

		raise notice 'Slony-I: log switch to sl_log_2 complete - truncate sl_log_1';
		truncate "_primer_cluster2".sl_log_1;
		if exists (select * from "pg_catalog".pg_class c, "pg_catalog".pg_namespace n, "pg_catalog".pg_attribute a where c.relname = 'sl_log_1' and n.oid = c.relnamespace and a.attrelid = c.oid and a.attname = 'oid') then
	                execute 'alter table "_primer_cluster2".sl_log_1 set without oids;';
		end if;		
		perform "pg_catalog".setval('"_primer_cluster2".sl_log_status', 1);
		-- Run addPartialLogIndices() to try to add indices to unused sl_log_? table
		perform "_primer_cluster2".addPartialLogIndices();
		return 2;
	end if;
END;
$$;


ALTER FUNCTION _primer_cluster2.logswitch_finish() OWNER TO postgres;

--
-- Name: FUNCTION logswitch_finish(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.logswitch_finish() IS 'logswitch_finish()

Attempt to finalize a log table switch in progress
return values:
  -1 if switch in progress, but not complete
   0 if no switch in progress
   1 if performed truncate on sl_log_2
   2 if performed truncate on sl_log_1
';


--
-- Name: logswitch_start(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.logswitch_start() RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_current_status	int4;
BEGIN
	-- ----
	-- Get the current log status.
	-- ----
	select last_value into v_current_status from "_primer_cluster2".sl_log_status;

	-- ----
	-- status = 0: sl_log_1 active, sl_log_2 clean
	-- Initiate a switch to sl_log_2.
	-- ----
	if v_current_status = 0 then
		perform "pg_catalog".setval('"_primer_cluster2".sl_log_status', 3);
		perform "_primer_cluster2".registry_set_timestamp(
				'logswitch.laststart', now());
		raise notice 'Slony-I: Logswitch to sl_log_2 initiated';
		return 2;
	end if;

	-- ----
	-- status = 1: sl_log_2 active, sl_log_1 clean
	-- Initiate a switch to sl_log_1.
	-- ----
	if v_current_status = 1 then
		perform "pg_catalog".setval('"_primer_cluster2".sl_log_status', 2);
		perform "_primer_cluster2".registry_set_timestamp(
				'logswitch.laststart', now());
		raise notice 'Slony-I: Logswitch to sl_log_1 initiated';
		return 1;
	end if;

	raise exception 'Previous logswitch still in progress';
END;
$$;


ALTER FUNCTION _primer_cluster2.logswitch_start() OWNER TO postgres;

--
-- Name: FUNCTION logswitch_start(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.logswitch_start() IS 'logswitch_start()

Initiate a log table switch if none is in progress';


--
-- Name: logtrigger(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.logtrigger() RETURNS trigger
    LANGUAGE c SECURITY DEFINER
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_logTrigger';


ALTER FUNCTION _primer_cluster2.logtrigger() OWNER TO postgres;

--
-- Name: FUNCTION logtrigger(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.logtrigger() IS 'This is the trigger that is executed on the origin node that causes
updates to be recorded in sl_log_1/sl_log_2.';


--
-- Name: mergeset(integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.mergeset(p_set_id integer, p_add_id integer) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	v_origin			int4;
	in_progress			boolean;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Check that both sets exist and originate here
	-- ----
	if p_set_id = p_add_id then
		raise exception 'Slony-I: merged set ids cannot be identical';
	end if;
	select set_origin into v_origin from "_primer_cluster2".sl_set
			where set_id = p_set_id;
	if not found then
		raise exception 'Slony-I: set % not found', p_set_id;
	end if;
	if v_origin != "_primer_cluster2".getLocalNodeId('_primer_cluster2') then
		raise exception 'Slony-I: set % does not originate on local node',
				p_set_id;
	end if;

	select set_origin into v_origin from "_primer_cluster2".sl_set
			where set_id = p_add_id;
	if not found then
		raise exception 'Slony-I: set % not found', p_add_id;
	end if;
	if v_origin != "_primer_cluster2".getLocalNodeId('_primer_cluster2') then
		raise exception 'Slony-I: set % does not originate on local node',
				p_add_id;
	end if;

	-- ----
	-- Check that both sets are subscribed by the same set of nodes
	-- ----
	if exists (select true from "_primer_cluster2".sl_subscribe SUB1
				where SUB1.sub_set = p_set_id
				and SUB1.sub_receiver not in (select SUB2.sub_receiver
						from "_primer_cluster2".sl_subscribe SUB2
						where SUB2.sub_set = p_add_id))
	then
		raise exception 'Slony-I: subscriber lists of set % and % are different',
				p_set_id, p_add_id;
	end if;

	if exists (select true from "_primer_cluster2".sl_subscribe SUB1
				where SUB1.sub_set = p_add_id
				and SUB1.sub_receiver not in (select SUB2.sub_receiver
						from "_primer_cluster2".sl_subscribe SUB2
						where SUB2.sub_set = p_set_id))
	then
		raise exception 'Slony-I: subscriber lists of set % and % are different',
				p_add_id, p_set_id;
	end if;

	-- ----
	-- Check that all ENABLE_SUBSCRIPTION events for the set are confirmed
	-- ----
	select "_primer_cluster2".isSubscriptionInProgress(p_add_id) into in_progress ;
	
	if in_progress then
		raise exception 'Slony-I: set % has subscriptions in progress - cannot merge',
				p_add_id;
	end if;

	-- ----
	-- Create a SYNC event, merge the sets, create a MERGE_SET event
	-- ----
	perform "_primer_cluster2".createEvent('_primer_cluster2', 'SYNC', NULL);
	perform "_primer_cluster2".mergeSet_int(p_set_id, p_add_id);
	return  "_primer_cluster2".createEvent('_primer_cluster2', 'MERGE_SET', 
			p_set_id::text, p_add_id::text);
end;
$$;


ALTER FUNCTION _primer_cluster2.mergeset(p_set_id integer, p_add_id integer) OWNER TO postgres;

--
-- Name: FUNCTION mergeset(p_set_id integer, p_add_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.mergeset(p_set_id integer, p_add_id integer) IS 'Generate MERGE_SET event to request that sets be merged together.

Both sets must exist, and originate on the same node.  They must be
subscribed by the same set of nodes.';


--
-- Name: mergeset_int(integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.mergeset_int(p_set_id integer, p_add_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	update "_primer_cluster2".sl_sequence
			set seq_set = p_set_id
			where seq_set = p_add_id;
	update "_primer_cluster2".sl_table
			set tab_set = p_set_id
			where tab_set = p_add_id;
	delete from "_primer_cluster2".sl_subscribe
			where sub_set = p_add_id;
	delete from "_primer_cluster2".sl_setsync
			where ssy_setid = p_add_id;
	delete from "_primer_cluster2".sl_set
			where set_id = p_add_id;

	return p_set_id;
end;
$$;


ALTER FUNCTION _primer_cluster2.mergeset_int(p_set_id integer, p_add_id integer) OWNER TO postgres;

--
-- Name: FUNCTION mergeset_int(p_set_id integer, p_add_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.mergeset_int(p_set_id integer, p_add_id integer) IS 'mergeSet_int(set_id, add_id) - Perform MERGE_SET event, merging all objects from 
set add_id into set set_id.';


--
-- Name: moveset(integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.moveset(p_set_id integer, p_new_origin integer) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	v_local_node_id		int4;
	v_set_row			record;
	v_sub_row			record;
	v_sync_seqno		int8;
	v_lv_row			record;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Check that the set is locked and that this locking
	-- happened long enough ago.
	-- ----
	v_local_node_id := "_primer_cluster2".getLocalNodeId('_primer_cluster2');
	select * into v_set_row from "_primer_cluster2".sl_set
			where set_id = p_set_id
			for update;
	if not found then
		raise exception 'Slony-I: set % not found', p_set_id;
	end if;
	if v_set_row.set_origin <> v_local_node_id then
		raise exception 'Slony-I: set % does not originate on local node',
				p_set_id;
	end if;
	if v_set_row.set_locked isnull then
		raise exception 'Slony-I: set % is not locked', p_set_id;
	end if;
	if v_set_row.set_locked > "pg_catalog".txid_snapshot_xmin("pg_catalog".txid_current_snapshot()) then
		raise exception 'Slony-I: cannot move set % yet, transactions < % are still in progress',
				p_set_id, v_set_row.set_locked;
	end if;

	-- ----
	-- Unlock the set
	-- ----
	perform "_primer_cluster2".unlockSet(p_set_id);

	-- ----
	-- Check that the new_origin is an active subscriber of the set
	-- ----
	select * into v_sub_row from "_primer_cluster2".sl_subscribe
			where sub_set = p_set_id
			and sub_receiver = p_new_origin;
	if not found then
		raise exception 'Slony-I: set % is not subscribed by node %',
				p_set_id, p_new_origin;
	end if;
	if not v_sub_row.sub_active then
		raise exception 'Slony-I: subsctiption of node % for set % is inactive',
				p_new_origin, p_set_id;
	end if;

	-- ----
	-- Reconfigure everything
	-- ----
	perform "_primer_cluster2".moveSet_int(p_set_id, v_local_node_id,
			p_new_origin, 0);

	perform "_primer_cluster2".RebuildListenEntries();

	-- ----
	-- At this time we hold access exclusive locks for every table
	-- in the set. But we did move the set to the new origin, so the
	-- createEvent() we are doing now will not record the sequences.
	-- ----
	v_sync_seqno := "_primer_cluster2".createEvent('_primer_cluster2', 'SYNC');
	insert into "_primer_cluster2".sl_seqlog 
			(seql_seqid, seql_origin, seql_ev_seqno, seql_last_value)
			select seq_id, v_local_node_id, v_sync_seqno, seq_last_value
			from "_primer_cluster2".sl_seqlastvalue
			where seq_set = p_set_id;
					
	-- ----
	-- Finally we generate the real event
	-- ----
	return "_primer_cluster2".createEvent('_primer_cluster2', 'MOVE_SET', 
			p_set_id::text, v_local_node_id::text, p_new_origin::text);
end;
$$;


ALTER FUNCTION _primer_cluster2.moveset(p_set_id integer, p_new_origin integer) OWNER TO postgres;

--
-- Name: FUNCTION moveset(p_set_id integer, p_new_origin integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.moveset(p_set_id integer, p_new_origin integer) IS 'moveSet(set_id, new_origin)

Generate MOVE_SET event to request that the origin for set set_id be moved to node new_origin';


--
-- Name: moveset_int(integer, integer, integer, bigint); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.moveset_int(p_set_id integer, p_old_origin integer, p_new_origin integer, p_wait_seqno bigint) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_local_node_id		int4;
	v_tab_row			record;
	v_sub_row			record;
	v_sub_node			int4;
	v_sub_last			int4;
	v_sub_next			int4;
	v_last_sync			int8;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Get our local node ID
	-- ----
	v_local_node_id := "_primer_cluster2".getLocalNodeId('_primer_cluster2');

	-- On the new origin, raise an event - ACCEPT_SET
	if v_local_node_id = p_new_origin then
		-- Create a SYNC event as well so that the ACCEPT_SET has
		-- the same snapshot as the last SYNC generated by the new
		-- origin. This snapshot will be used by other nodes to
		-- finalize the setsync status.
		perform "_primer_cluster2".createEvent('_primer_cluster2', 'SYNC', NULL);
		perform "_primer_cluster2".createEvent('_primer_cluster2', 'ACCEPT_SET', 
			p_set_id::text, p_old_origin::text, 
			p_new_origin::text, p_wait_seqno::text);
	end if;

	-- ----
	-- Next we have to reverse the subscription path
	-- ----
	v_sub_last = p_new_origin;
	select sub_provider into v_sub_node
			from "_primer_cluster2".sl_subscribe
			where sub_set = p_set_id
			and sub_receiver = p_new_origin;
	if not found then
		raise exception 'Slony-I: subscription path broken in moveSet_int';
	end if;
	while v_sub_node <> p_old_origin loop
		-- ----
		-- Tracing node by node, the old receiver is now in
		-- v_sub_last and the old provider is in v_sub_node.
		-- ----

		-- ----
		-- Get the current provider of this node as next
		-- and change the provider to the previous one in
		-- the reverse chain.
		-- ----
		select sub_provider into v_sub_next
				from "_primer_cluster2".sl_subscribe
				where sub_set = p_set_id
					and sub_receiver = v_sub_node
				for update;
		if not found then
			raise exception 'Slony-I: subscription path broken in moveSet_int';
		end if;
		update "_primer_cluster2".sl_subscribe
				set sub_provider = v_sub_last
				where sub_set = p_set_id
					and sub_receiver = v_sub_node
					and sub_receiver <> v_sub_last;

		v_sub_last = v_sub_node;
		v_sub_node = v_sub_next;
	end loop;

	-- ----
	-- This includes creating a subscription for the old origin
	-- ----
	insert into "_primer_cluster2".sl_subscribe
			(sub_set, sub_provider, sub_receiver,
			sub_forward, sub_active)
			values (p_set_id, v_sub_last, p_old_origin, true, true);
	if v_local_node_id = p_old_origin then
		select coalesce(max(ev_seqno), 0) into v_last_sync 
				from "_primer_cluster2".sl_event
				where ev_origin = p_new_origin
					and ev_type = 'SYNC';
		if v_last_sync > 0 then
			insert into "_primer_cluster2".sl_setsync
					(ssy_setid, ssy_origin, ssy_seqno,
					ssy_snapshot, ssy_action_list)
					select p_set_id, p_new_origin, v_last_sync,
					ev_snapshot, NULL
					from "_primer_cluster2".sl_event
					where ev_origin = p_new_origin
						and ev_seqno = v_last_sync;
		else
			insert into "_primer_cluster2".sl_setsync
					(ssy_setid, ssy_origin, ssy_seqno,
					ssy_snapshot, ssy_action_list)
					values (p_set_id, p_new_origin, '0',
					'1:1:', NULL);
		end if;
	end if;

	-- ----
	-- Now change the ownership of the set.
	-- ----
	update "_primer_cluster2".sl_set
			set set_origin = p_new_origin
			where set_id = p_set_id;

	-- ----
	-- On the new origin, delete the obsolete setsync information
	-- and the subscription.
	-- ----
	if v_local_node_id = p_new_origin then
		delete from "_primer_cluster2".sl_setsync
				where ssy_setid = p_set_id;
	else
		if v_local_node_id <> p_old_origin then
			--
			-- On every other node, change the setsync so that it will
			-- pick up from the new origins last known sync.
			--
			delete from "_primer_cluster2".sl_setsync
					where ssy_setid = p_set_id;
			select coalesce(max(ev_seqno), 0) into v_last_sync
					from "_primer_cluster2".sl_event
					where ev_origin = p_new_origin
						and ev_type = 'SYNC';
			if v_last_sync > 0 then
				insert into "_primer_cluster2".sl_setsync
						(ssy_setid, ssy_origin, ssy_seqno,
						ssy_snapshot, ssy_action_list)
						select p_set_id, p_new_origin, v_last_sync,
						ev_snapshot, NULL
						from "_primer_cluster2".sl_event
						where ev_origin = p_new_origin
							and ev_seqno = v_last_sync;
			else
				insert into "_primer_cluster2".sl_setsync
						(ssy_setid, ssy_origin, ssy_seqno,
						ssy_snapshot, ssy_action_list)
						values (p_set_id, p_new_origin,
						'0', '1:1:', NULL);
			end if;
		end if;
	end if;
	delete from "_primer_cluster2".sl_subscribe
			where sub_set = p_set_id
			and sub_receiver = p_new_origin;

	-- Regenerate sl_listen since we revised the subscriptions
	perform "_primer_cluster2".RebuildListenEntries();

	-- Run addPartialLogIndices() to try to add indices to unused sl_log_? table
	perform "_primer_cluster2".addPartialLogIndices();

	-- ----
	-- If we are the new or old origin, we have to
	-- adjust the log and deny access trigger configuration.
	-- ----
	if v_local_node_id = p_old_origin or v_local_node_id = p_new_origin then
		for v_tab_row in select tab_id from "_primer_cluster2".sl_table
				where tab_set = p_set_id
				order by tab_id
		loop
			perform "_primer_cluster2".alterTableConfigureTriggers(v_tab_row.tab_id);
		end loop;
	end if;

	return p_set_id;
end;
$$;


ALTER FUNCTION _primer_cluster2.moveset_int(p_set_id integer, p_old_origin integer, p_new_origin integer, p_wait_seqno bigint) OWNER TO postgres;

--
-- Name: FUNCTION moveset_int(p_set_id integer, p_old_origin integer, p_new_origin integer, p_wait_seqno bigint); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.moveset_int(p_set_id integer, p_old_origin integer, p_new_origin integer, p_wait_seqno bigint) IS 'moveSet(set_id, old_origin, new_origin, wait_seqno)

Process MOVE_SET event to request that the origin for set set_id be
moved from old_origin to node new_origin';


--
-- Name: prefailover(integer, boolean); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.prefailover(p_failed_node integer, p_is_candidate boolean) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_row				record;
	v_row2				record;
	v_n					int4;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- All consistency checks first

	if p_is_candidate then
	   -- ----
	   -- Check all sets originating on the failed node
	   -- ----
	   for v_row in select set_id
			from "_primer_cluster2".sl_set
			where set_origin = p_failed_node
		loop
				-- ----
				-- Check that the backup node is subscribed to all sets
				-- that originate on the failed node
				-- ----
				select into v_row2 sub_forward, sub_active
					   from "_primer_cluster2".sl_subscribe
					   where sub_set = v_row.set_id
					and sub_receiver = "_primer_cluster2".getLocalNodeId('_primer_cluster2');
				if not found then
				   raise exception 'Slony-I: cannot failover - node % is not subscribed to set %',
					"_primer_cluster2".getLocalNodeId('_primer_cluster2'), v_row.set_id;
				end if;

				-- ----
				-- Check that the subscription is active
				-- ----
				if not v_row2.sub_active then
				   raise exception 'Slony-I: cannot failover - subscription for set % is not active',
					v_row.set_id;
				end if;

				-- ----
				-- If there are other subscribers, the backup node needs to
				-- be a forwarder too.
				-- ----
				select into v_n count(*)
					   from "_primer_cluster2".sl_subscribe
					   where sub_set = v_row.set_id
					   and sub_receiver <> "_primer_cluster2".getLocalNodeId('_primer_cluster2');
				if v_n > 0 and not v_row2.sub_forward then
				raise exception 'Slony-I: cannot failover - node % is not a forwarder of set %',
					 "_primer_cluster2".getLocalNodeId('_primer_cluster2'), v_row.set_id;
				end if;
			end loop;
	end if;

	-- ----
	-- Terminate all connections of the failed node the hard way
	-- ----
	perform "_primer_cluster2".terminateNodeConnections(p_failed_node);

	update "_primer_cluster2".sl_path set pa_conninfo='<event pending>' WHERE
	   		  pa_server=p_failed_node;	
	notify "_primer_cluster2_Restart";
	-- ----
	-- That is it - so far.
	-- ----
	return p_failed_node;
end;
$$;


ALTER FUNCTION _primer_cluster2.prefailover(p_failed_node integer, p_is_candidate boolean) OWNER TO postgres;

--
-- Name: FUNCTION prefailover(p_failed_node integer, p_is_candidate boolean); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.prefailover(p_failed_node integer, p_is_candidate boolean) IS 'Prepare for a failover.  This function is called on all candidate nodes.
It blanks the paths to the failed node
and then restart of all node daemons.';


--
-- Name: preparetableforcopy(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.preparetableforcopy(p_tab_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_tab_oid		oid;
	v_tab_fqname	text;
begin
	-- ----
	-- Get the OID and fully qualified name for the table
	-- ---
	select	PGC.oid,
			"_primer_cluster2".slon_quote_brute(PGN.nspname) || '.' ||
			"_primer_cluster2".slon_quote_brute(PGC.relname) as tab_fqname
		into v_tab_oid, v_tab_fqname
			from "_primer_cluster2".sl_table T,   
				"pg_catalog".pg_class PGC, "pg_catalog".pg_namespace PGN
				where T.tab_id = p_tab_id
				and T.tab_reloid = PGC.oid
				and PGC.relnamespace = PGN.oid;
	if not found then
		raise exception 'Table with ID % not found in sl_table', p_tab_id;
	end if;

	-- ----
	-- Try using truncate to empty the table and fallback to
	-- delete on error.
	-- ----
	perform "_primer_cluster2".TruncateOnlyTable(v_tab_fqname);
	raise notice 'truncate of % succeeded', v_tab_fqname;

	-- suppress index activity
        perform "_primer_cluster2".disable_indexes_on_table(v_tab_oid);

	return 1;
	exception when others then
		raise notice 'truncate of % failed - doing delete', v_tab_fqname;
		perform "_primer_cluster2".disable_indexes_on_table(v_tab_oid);
		execute 'delete from only ' || "_primer_cluster2".slon_quote_input(v_tab_fqname);
		return 0;
end;
$$;


ALTER FUNCTION _primer_cluster2.preparetableforcopy(p_tab_id integer) OWNER TO postgres;

--
-- Name: FUNCTION preparetableforcopy(p_tab_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.preparetableforcopy(p_tab_id integer) IS 'Delete all data and suppress index maintenance';


--
-- Name: rebuildlistenentries(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.rebuildlistenentries() RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_row	record;
        v_cnt  integer;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- First remove the entire configuration
	delete from "_primer_cluster2".sl_listen;

	-- Second populate the sl_listen configuration with a full
	-- network of all possible paths.
	insert into "_primer_cluster2".sl_listen
				(li_origin, li_provider, li_receiver)
			select pa_server, pa_server, pa_client from "_primer_cluster2".sl_path;
	while true loop
		insert into "_primer_cluster2".sl_listen
					(li_origin, li_provider, li_receiver)
			select distinct li_origin, pa_server, pa_client
				from "_primer_cluster2".sl_listen, "_primer_cluster2".sl_path
				where li_receiver = pa_server
				  and li_origin <> pa_client
				  and pa_conninfo<>'<event pending>'
			except
			select li_origin, li_provider, li_receiver
				from "_primer_cluster2".sl_listen;

		if not found then
			exit;
		end if;
	end loop;

	-- We now replace specific event-origin,receiver combinations
	-- with a configuration that tries to avoid events arriving at
	-- a node before the data provider actually has the data ready.

	-- Loop over every possible pair of receiver and event origin
	for v_row in select N1.no_id as receiver, N2.no_id as origin,
			  N2.no_failed as failed
			from "_primer_cluster2".sl_node as N1, "_primer_cluster2".sl_node as N2
			where N1.no_id <> N2.no_id
	loop
		-- 1st choice:
		-- If we use the event origin as a data provider for any
		-- set that originates on that very node, we are a direct
		-- subscriber to that origin and listen there only.
		if exists (select true from "_primer_cluster2".sl_set, "_primer_cluster2".sl_subscribe				, "_primer_cluster2".sl_node p		   		
				where set_origin = v_row.origin
				  and sub_set = set_id
				  and sub_provider = v_row.origin
				  and sub_receiver = v_row.receiver
				  and sub_active
				  and p.no_active
				  and p.no_id=sub_provider
				  )
		then
			delete from "_primer_cluster2".sl_listen
				where li_origin = v_row.origin
				  and li_receiver = v_row.receiver;
			insert into "_primer_cluster2".sl_listen (li_origin, li_provider, li_receiver)
				values (v_row.origin, v_row.origin, v_row.receiver);
		
		-- 2nd choice:
		-- If we are subscribed to any set originating on this
		-- event origin, we want to listen on all data providers
		-- we use for this origin. We are a cascaded subscriber
		-- for sets from this node.
		else
				if exists (select true from "_primer_cluster2".sl_set, "_primer_cluster2".sl_subscribe,
				   	  	       "_primer_cluster2".sl_node provider
						where set_origin = v_row.origin
						  and sub_set = set_id
						  and sub_provider=provider.no_id
						  and provider.no_failed = false
						  and sub_receiver = v_row.receiver
						  and sub_active)
				then
						delete from "_primer_cluster2".sl_listen
							   where li_origin = v_row.origin
					  		   and li_receiver = v_row.receiver;
						insert into "_primer_cluster2".sl_listen (li_origin, li_provider, li_receiver)
						select distinct set_origin, sub_provider, v_row.receiver
							   from "_primer_cluster2".sl_set, "_primer_cluster2".sl_subscribe
						where set_origin = v_row.origin
						  and sub_set = set_id
						  and sub_receiver = v_row.receiver
						  and sub_active;
				end if;
		end if;

		if v_row.failed then		

		--for every failed node we delete all sl_listen entries
		--except via providers (listed in sl_subscribe)
		--or failover candidates (sl_failover_targets)
		--we do this to prevent a non-failover candidate
		--that is more ahead of the failover candidate from
		--sending events to the failover candidate that
		--are 'too far ahead'

		--if the failed node is not an origin for any
                --node then we don't delete all listen paths
		--for events from it.  Instead we leave
                --the listen network alone.
		
		select count(*) into v_cnt from "_primer_cluster2".sl_subscribe sub,
		       "_primer_cluster2".sl_set s
                       where s.set_origin=v_row.origin and s.set_id=sub.sub_set;
                if v_cnt > 0 then
		    delete from "_primer_cluster2".sl_listen where
			   li_origin=v_row.origin and
			   li_receiver=v_row.receiver			
			   and li_provider not in 
			       (select sub_provider from
			       "_primer_cluster2".sl_subscribe,
			       "_primer_cluster2".sl_set where
			       sub_set=set_id
			       and set_origin=v_row.origin);
		    end if;
               end if;
--		   insert into "_primer_cluster2".sl_listen
--		   		  (li_origin,li_provider,li_receiver)
--				  SELECT v_row.origin, pa_server
--				  ,v_row.receiver
--				  FROM "_primer_cluster2".sl_path where
--				  	   pa_client=v_row.receiver
--				  and (v_row.origin,pa_server,v_row.receiver) not in
--				  	  		(select li_origin,li_provider,li_receiver
--					  		from "_primer_cluster2".sl_listen);
--		end if;
	end loop ;

	return null ;
end ;
$$;


ALTER FUNCTION _primer_cluster2.rebuildlistenentries() OWNER TO postgres;

--
-- Name: FUNCTION rebuildlistenentries(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.rebuildlistenentries() IS 'RebuildListenEntries()

Invoked by various subscription and path modifying functions, this
rewrites the sl_listen entries, adding in all the ones required to
allow communications between nodes in the Slony-I cluster.';


--
-- Name: recreate_log_trigger(text, oid, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.recreate_log_trigger(p_fq_table_name text, p_tab_id oid, p_tab_attkind text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
	execute 'drop trigger "_primer_cluster2_logtrigger" on ' ||
		p_fq_table_name	;
		-- ----
	execute 'create trigger "_primer_cluster2_logtrigger"' || 
			' after insert or update or delete on ' ||
			p_fq_table_name 
			|| ' for each row execute procedure "_primer_cluster2".logTrigger (' ||
                               pg_catalog.quote_literal('_primer_cluster2') || ',' || 
				pg_catalog.quote_literal(p_tab_id::text) || ',' || 
				pg_catalog.quote_literal(p_tab_attkind) || ');';
	return 0;
end
$$;


ALTER FUNCTION _primer_cluster2.recreate_log_trigger(p_fq_table_name text, p_tab_id oid, p_tab_attkind text) OWNER TO postgres;

--
-- Name: FUNCTION recreate_log_trigger(p_fq_table_name text, p_tab_id oid, p_tab_attkind text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.recreate_log_trigger(p_fq_table_name text, p_tab_id oid, p_tab_attkind text) IS 'A function that drops and recreates the log trigger on the specified table.
It is intended to be used after the primary_key/unique index has changed.';


--
-- Name: registernodeconnection(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.registernodeconnection(p_nodeid integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
	insert into "_primer_cluster2".sl_nodelock
		(nl_nodeid, nl_backendpid)
		values
		(p_nodeid, pg_backend_pid());

	return 0;
end;
$$;


ALTER FUNCTION _primer_cluster2.registernodeconnection(p_nodeid integer) OWNER TO postgres;

--
-- Name: FUNCTION registernodeconnection(p_nodeid integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.registernodeconnection(p_nodeid integer) IS 'Register (uniquely) the node connection so that only one slon can service the node';


--
-- Name: registry_get_int4(text, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.registry_get_int4(p_key text, p_default integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_value		int4;
BEGIN
	select reg_int4 into v_value from "_primer_cluster2".sl_registry
			where reg_key = p_key;
	if not found then 
		v_value = p_default;
		if p_default notnull then
			perform "_primer_cluster2".registry_set_int4(p_key, p_default);
		end if;
	else
		if v_value is null then
			raise exception 'Slony-I: registry key % is not an int4 value',
					p_key;
		end if;
	end if;
	return v_value;
END;
$$;


ALTER FUNCTION _primer_cluster2.registry_get_int4(p_key text, p_default integer) OWNER TO postgres;

--
-- Name: FUNCTION registry_get_int4(p_key text, p_default integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.registry_get_int4(p_key text, p_default integer) IS 'registry_get_int4(key, value)

Get a registry value. If not present, set and return the default.';


--
-- Name: registry_get_text(text, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.registry_get_text(p_key text, p_default text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_value		text;
BEGIN
	select reg_text into v_value from "_primer_cluster2".sl_registry
			where reg_key = p_key;
	if not found then 
		v_value = p_default;
		if p_default notnull then
			perform "_primer_cluster2".registry_set_text(p_key, p_default);
		end if;
	else
		if v_value is null then
			raise exception 'Slony-I: registry key % is not a text value',
					p_key;
		end if;
	end if;
	return v_value;
END;
$$;


ALTER FUNCTION _primer_cluster2.registry_get_text(p_key text, p_default text) OWNER TO postgres;

--
-- Name: FUNCTION registry_get_text(p_key text, p_default text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.registry_get_text(p_key text, p_default text) IS 'registry_get_text(key, value)

Get a registry value. If not present, set and return the default.';


--
-- Name: registry_get_timestamp(text, timestamp with time zone); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.registry_get_timestamp(p_key text, p_default timestamp with time zone) RETURNS timestamp without time zone
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_value		timestamp;
BEGIN
	select reg_timestamp into v_value from "_primer_cluster2".sl_registry
			where reg_key = p_key;
	if not found then 
		v_value = p_default;
		if p_default notnull then
			perform "_primer_cluster2".registry_set_timestamp(p_key, p_default);
		end if;
	else
		if v_value is null then
			raise exception 'Slony-I: registry key % is not an timestamp value',
					p_key;
		end if;
	end if;
	return v_value;
END;
$$;


ALTER FUNCTION _primer_cluster2.registry_get_timestamp(p_key text, p_default timestamp with time zone) OWNER TO postgres;

--
-- Name: FUNCTION registry_get_timestamp(p_key text, p_default timestamp with time zone); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.registry_get_timestamp(p_key text, p_default timestamp with time zone) IS 'registry_get_timestamp(key, value)

Get a registry value. If not present, set and return the default.';


--
-- Name: registry_set_int4(text, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.registry_set_int4(p_key text, p_value integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
BEGIN
	if p_value is null then
		delete from "_primer_cluster2".sl_registry
				where reg_key = p_key;
	else
		lock table "_primer_cluster2".sl_registry;
		update "_primer_cluster2".sl_registry
				set reg_int4 = p_value
				where reg_key = p_key;
		if not found then
			insert into "_primer_cluster2".sl_registry (reg_key, reg_int4)
					values (p_key, p_value);
		end if;
	end if;
	return p_value;
END;
$$;


ALTER FUNCTION _primer_cluster2.registry_set_int4(p_key text, p_value integer) OWNER TO postgres;

--
-- Name: FUNCTION registry_set_int4(p_key text, p_value integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.registry_set_int4(p_key text, p_value integer) IS 'registry_set_int4(key, value)

Set or delete a registry value';


--
-- Name: registry_set_text(text, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.registry_set_text(p_key text, p_value text) RETURNS text
    LANGUAGE plpgsql
    AS $$
BEGIN
	if p_value is null then
		delete from "_primer_cluster2".sl_registry
				where reg_key = p_key;
	else
		lock table "_primer_cluster2".sl_registry;
		update "_primer_cluster2".sl_registry
				set reg_text = p_value
				where reg_key = p_key;
		if not found then
			insert into "_primer_cluster2".sl_registry (reg_key, reg_text)
					values (p_key, p_value);
		end if;
	end if;
	return p_value;
END;
$$;


ALTER FUNCTION _primer_cluster2.registry_set_text(p_key text, p_value text) OWNER TO postgres;

--
-- Name: FUNCTION registry_set_text(p_key text, p_value text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.registry_set_text(p_key text, p_value text) IS 'registry_set_text(key, value)

Set or delete a registry value';


--
-- Name: registry_set_timestamp(text, timestamp with time zone); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.registry_set_timestamp(p_key text, p_value timestamp with time zone) RETURNS timestamp without time zone
    LANGUAGE plpgsql
    AS $$
BEGIN
	if p_value is null then
		delete from "_primer_cluster2".sl_registry
				where reg_key = p_key;
	else
		lock table "_primer_cluster2".sl_registry;
		update "_primer_cluster2".sl_registry
				set reg_timestamp = p_value
				where reg_key = p_key;
		if not found then
			insert into "_primer_cluster2".sl_registry (reg_key, reg_timestamp)
					values (p_key, p_value);
		end if;
	end if;
	return p_value;
END;
$$;


ALTER FUNCTION _primer_cluster2.registry_set_timestamp(p_key text, p_value timestamp with time zone) OWNER TO postgres;

--
-- Name: FUNCTION registry_set_timestamp(p_key text, p_value timestamp with time zone); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.registry_set_timestamp(p_key text, p_value timestamp with time zone) IS 'registry_set_timestamp(key, value)

Set or delete a registry value';


--
-- Name: repair_log_triggers(boolean); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.repair_log_triggers(only_locked boolean) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	retval integer;
	table_row record;
begin
	retval=0;
	for table_row in	
		select  tab_nspname,tab_relname,
				tab_idxname, tab_id, mode,
				"_primer_cluster2".determineAttKindUnique(tab_nspname||
					'.'||tab_relname,tab_idxname) as attkind
		from
				"_primer_cluster2".sl_table
				left join 
				pg_locks on (relation=tab_reloid and pid=pg_backend_pid()
				and mode='AccessExclusiveLock')				
				,pg_trigger
		where tab_reloid=tgrelid and 
		"_primer_cluster2".determineAttKindUnique(tab_nspname||'.'
						||tab_relname,tab_idxname)
			!=("_primer_cluster2".decode_tgargs(tgargs))[2]
			and tgname =  '_primer_cluster2'
			|| '_logtrigger'
		LOOP
				if (only_locked=false) or table_row.mode='AccessExclusiveLock' then
					 perform "_primer_cluster2".recreate_log_trigger
					 		 (table_row.tab_nspname||'.'||table_row.tab_relname,
							 table_row.tab_id,table_row.attkind);
					retval=retval+1;
				else 
					 raise notice '%.% has an invalid configuration on the log trigger. This was not corrected because only_lock is true and the table is not locked.',
					 table_row.tab_nspname,table_row.tab_relname;
			
				end if;
		end loop;
	return retval;
end
$$;


ALTER FUNCTION _primer_cluster2.repair_log_triggers(only_locked boolean) OWNER TO postgres;

--
-- Name: FUNCTION repair_log_triggers(only_locked boolean); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.repair_log_triggers(only_locked boolean) IS '
repair the log triggers as required.  If only_locked is true then only 
tables that are already exclusively locked by the current transaction are 
repaired. Otherwise all replicated tables with outdated trigger arguments
are recreated.';


--
-- Name: replicate_partition(integer, text, text, text, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.replicate_partition(p_tab_id integer, p_nspname text, p_tabname text, p_idxname text, p_comment text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
  prec record;
  prec2 record;
  v_set_id int4;

begin
-- Look up the parent table; fail if it does not exist
   select c1.oid into prec from pg_catalog.pg_class c1, pg_catalog.pg_class c2, pg_catalog.pg_inherits i, pg_catalog.pg_namespace n where c1.oid = i.inhparent  and c2.oid = i.inhrelid and n.oid = c2.relnamespace and n.nspname = p_nspname and c2.relname = p_tabname;
   if not found then
	raise exception 'replicate_partition: No parent table found for %.%!', p_nspname, p_tabname;
   end if;

-- The parent table tells us what replication set to use
   select tab_set into prec2 from "_primer_cluster2".sl_table where tab_reloid = prec.oid;
   if not found then
	raise exception 'replicate_partition: Parent table % for new partition %.% is not replicated!', prec.oid, p_nspname, p_tabname;
   end if;

   v_set_id := prec2.tab_set;

-- Now, we have all the parameters necessary to run add_empty_table_to_replication...
   return "_primer_cluster2".add_empty_table_to_replication(v_set_id, p_tab_id, p_nspname, p_tabname, p_idxname, p_comment);
end
$$;


ALTER FUNCTION _primer_cluster2.replicate_partition(p_tab_id integer, p_nspname text, p_tabname text, p_idxname text, p_comment text) OWNER TO postgres;

--
-- Name: FUNCTION replicate_partition(p_tab_id integer, p_nspname text, p_tabname text, p_idxname text, p_comment text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.replicate_partition(p_tab_id integer, p_nspname text, p_tabname text, p_idxname text, p_comment text) IS 'Add a partition table to replication.
tab_idxname is optional - if NULL, then we use the primary key.
This function looks up replication configuration via the parent table.

Note that this function is to be run within an EXECUTE SCRIPT script,
so it runs at the right place in the transaction stream on all
nodes.';


--
-- Name: resetsession(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.resetsession() RETURNS text
    LANGUAGE c
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_resetSession';


ALTER FUNCTION _primer_cluster2.resetsession() OWNER TO postgres;

--
-- Name: reshapesubscription(integer, integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.reshapesubscription(p_sub_origin integer, p_sub_provider integer, p_sub_receiver integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
	update "_primer_cluster2".sl_subscribe
		   set sub_provider=p_sub_provider
		   from "_primer_cluster2".sl_set
		   WHERE sub_set=sl_set.set_id
		   and sl_set.set_origin=p_sub_origin and sub_receiver=p_sub_receiver;
	if found then
	   perform "_primer_cluster2".RebuildListenEntries();
	   notify "_primer_cluster2_Restart";
	end if;
	return 0;
end
$$;


ALTER FUNCTION _primer_cluster2.reshapesubscription(p_sub_origin integer, p_sub_provider integer, p_sub_receiver integer) OWNER TO postgres;

--
-- Name: FUNCTION reshapesubscription(p_sub_origin integer, p_sub_provider integer, p_sub_receiver integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.reshapesubscription(p_sub_origin integer, p_sub_provider integer, p_sub_receiver integer) IS 'Run on a receiver/subscriber node when the provider for that
subscription is being changed.  Slonik will invoke this method
before the SUBSCRIBE_SET event propogates to the receiver
so listen paths can be updated.';


--
-- Name: resubscribenode(integer, integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.resubscribenode(p_origin integer, p_provider integer, p_receiver integer) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	v_record record;
	v_missing_sets text;
	v_ev_seqno bigint;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	--
	-- Check that the receiver exists
	--
	if not exists (select no_id from "_primer_cluster2".sl_node where no_id=
	       	      p_receiver) then
		      raise exception 'Slony-I: subscribeSet() receiver % does not exist' , p_receiver;
	end if;

	--
	-- Check that the provider exists
	--
	if not exists (select no_id from "_primer_cluster2".sl_node where no_id=
	       	      p_provider) then
		      raise exception 'Slony-I: subscribeSet() provider % does not exist' , p_provider;
	end if;

	
	-- ----
	-- Check that this is called on the origin node
	-- ----
	if p_origin != "_primer_cluster2".getLocalNodeId('_primer_cluster2') then
		raise exception 'Slony-I: subscribeSet() must be called on origin';
	end if;

	-- ---
	-- Verify that the provider is either the origin or an active subscriber
	-- Bug report #1362
	-- ---
	if p_origin <> p_provider then
	   for v_record in select sub1.sub_set from 
		    "_primer_cluster2".sl_subscribe sub1			
		    left outer join  ("_primer_cluster2".sl_subscribe sub2 
				 inner join
				 "_primer_cluster2".sl_set  on (
								sl_set.set_id=sub2.sub_set
								and sub2.sub_set=p_origin)
								)
			ON (  sub1.sub_set = sub2.sub_set and 
                  sub1.sub_receiver = p_provider and
			      sub1.sub_forward and sub1.sub_active
				  and sub2.sub_receiver=p_receiver)
		
			where sub2.sub_set is null 
		loop
				v_missing_sets=v_missing_sets || ' ' || v_record.sub_set;
		end loop;
		if v_missing_sets is not null then
			raise exception 'Slony-I: subscribeSet(): provider % is not an active forwarding node for replication set %', p_sub_provider, v_missing_sets;
		end if;
	end if;

	for v_record in select *  from 
		"_primer_cluster2".sl_subscribe, "_primer_cluster2".sl_set where 
		sub_set=set_id and
		sub_receiver=p_receiver
		and set_origin=p_origin
	loop
	-- ----
	-- Create the SUBSCRIBE_SET event
	-- ----
	   v_ev_seqno :=  "_primer_cluster2".createEvent('_primer_cluster2', 'SUBSCRIBE_SET', 
				  v_record.sub_set::text, p_provider::text, p_receiver::text, 
				  case v_record.sub_forward when true then 't' else 'f' end,
				  	   'f' );

		-- ----
		-- Call the internal procedure to store the subscription
		-- ----
		perform "_primer_cluster2".subscribeSet_int(v_record.sub_set, 
				p_provider,
				p_receiver, v_record.sub_forward, false);
	end loop;

	return v_ev_seqno;	
end;
$$;


ALTER FUNCTION _primer_cluster2.resubscribenode(p_origin integer, p_provider integer, p_receiver integer) OWNER TO postgres;

--
-- Name: seqtrack(integer, bigint); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.seqtrack(p_seqid integer, p_seqval bigint) RETURNS bigint
    LANGUAGE c STRICT
    AS '$libdir/slony1_funcs.2.2.6', '_Slony_I_2_2_6_seqtrack';


ALTER FUNCTION _primer_cluster2.seqtrack(p_seqid integer, p_seqval bigint) OWNER TO postgres;

--
-- Name: FUNCTION seqtrack(p_seqid integer, p_seqval bigint); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.seqtrack(p_seqid integer, p_seqval bigint) IS 'Returns NULL if seqval has not changed since the last call for seqid';


--
-- Name: sequencelastvalue(text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.sequencelastvalue(p_seqname text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	v_seq_row	record;
begin
	for v_seq_row in execute 'select last_value from ' || "_primer_cluster2".slon_quote_input(p_seqname)
	loop
		return v_seq_row.last_value;
	end loop;

	-- not reached
end;
$$;


ALTER FUNCTION _primer_cluster2.sequencelastvalue(p_seqname text) OWNER TO postgres;

--
-- Name: FUNCTION sequencelastvalue(p_seqname text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.sequencelastvalue(p_seqname text) IS 'sequenceLastValue(p_seqname)

Utility function used in sl_seqlastvalue view to compactly get the
last value from the requested sequence.';


--
-- Name: sequencesetvalue(integer, integer, bigint, bigint, boolean); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.sequencesetvalue(p_seq_id integer, p_seq_origin integer, p_ev_seqno bigint, p_last_value bigint, p_ignore_missing boolean) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_fqname			text;
	v_found                         integer;
begin
	-- ----
	-- Get the sequences fully qualified name
	-- ----
	select "_primer_cluster2".slon_quote_brute(PGN.nspname) || '.' ||
			"_primer_cluster2".slon_quote_brute(PGC.relname) into v_fqname
		from "_primer_cluster2".sl_sequence SQ,
			"pg_catalog".pg_class PGC, "pg_catalog".pg_namespace PGN
		where SQ.seq_id = p_seq_id
			and SQ.seq_reloid = PGC.oid
			and PGC.relnamespace = PGN.oid;
	if not found then
	        if p_ignore_missing then
                       return null;
                end if;
		raise exception 'Slony-I: sequenceSetValue(): sequence % not found', p_seq_id;
	end if;

	-- ----
	-- Update it to the new value
	-- ----
	execute 'select setval(''' || v_fqname ||
			''', ' || p_last_value::text || ')';

	if p_ev_seqno is not null then
	   insert into "_primer_cluster2".sl_seqlog
			(seql_seqid, seql_origin, seql_ev_seqno, seql_last_value)
			values (p_seq_id, p_seq_origin, p_ev_seqno, p_last_value);
	end if;
	return p_seq_id;
end;
$$;


ALTER FUNCTION _primer_cluster2.sequencesetvalue(p_seq_id integer, p_seq_origin integer, p_ev_seqno bigint, p_last_value bigint, p_ignore_missing boolean) OWNER TO postgres;

--
-- Name: FUNCTION sequencesetvalue(p_seq_id integer, p_seq_origin integer, p_ev_seqno bigint, p_last_value bigint, p_ignore_missing boolean); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.sequencesetvalue(p_seq_id integer, p_seq_origin integer, p_ev_seqno bigint, p_last_value bigint, p_ignore_missing boolean) IS 'sequenceSetValue (seq_id, seq_origin, ev_seqno, last_value,ignore_missing)
Set sequence seq_id to have new value last_value.
';


--
-- Name: setaddsequence(integer, integer, text, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.setaddsequence(p_set_id integer, p_seq_id integer, p_fqname text, p_seq_comment text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	v_set_origin		int4;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Check that we are the origin of the set
	-- ----
	select set_origin into v_set_origin
			from "_primer_cluster2".sl_set
			where set_id = p_set_id;
	if not found then
		raise exception 'Slony-I: setAddSequence(): set % not found', p_set_id;
	end if;
	if v_set_origin != "_primer_cluster2".getLocalNodeId('_primer_cluster2') then
		raise exception 'Slony-I: setAddSequence(): set % has remote origin - submit to origin node', p_set_id;
	end if;

	if exists (select true from "_primer_cluster2".sl_subscribe
			where sub_set = p_set_id)
	then
		raise exception 'Slony-I: cannot add sequence to currently subscribed set %',
				p_set_id;
	end if;

	-- ----
	-- Add the sequence to the set and generate the SET_ADD_SEQUENCE event
	-- ----
	perform "_primer_cluster2".setAddSequence_int(p_set_id, p_seq_id, p_fqname,
			p_seq_comment);
	return  "_primer_cluster2".createEvent('_primer_cluster2', 'SET_ADD_SEQUENCE',
						p_set_id::text, p_seq_id::text, 
						p_fqname::text, p_seq_comment::text);
end;
$$;


ALTER FUNCTION _primer_cluster2.setaddsequence(p_set_id integer, p_seq_id integer, p_fqname text, p_seq_comment text) OWNER TO postgres;

--
-- Name: FUNCTION setaddsequence(p_set_id integer, p_seq_id integer, p_fqname text, p_seq_comment text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.setaddsequence(p_set_id integer, p_seq_id integer, p_fqname text, p_seq_comment text) IS 'setAddSequence (set_id, seq_id, seq_fqname, seq_comment)

On the origin node for set set_id, add sequence seq_fqname to the
replication set, and raise SET_ADD_SEQUENCE to cause this to replicate
to subscriber nodes.';


--
-- Name: setaddsequence_int(integer, integer, text, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.setaddsequence_int(p_set_id integer, p_seq_id integer, p_fqname text, p_seq_comment text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_local_node_id		int4;
	v_set_origin		int4;
	v_sub_provider		int4;
	v_relkind			char;
	v_seq_reloid		oid;
	v_seq_relname		name;
	v_seq_nspname		name;
	v_sync_row			record;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- For sets with a remote origin, check that we are subscribed 
	-- to that set. Otherwise we ignore the sequence because it might 
	-- not even exist in our database.
	-- ----
	v_local_node_id := "_primer_cluster2".getLocalNodeId('_primer_cluster2');
	select set_origin into v_set_origin
			from "_primer_cluster2".sl_set
			where set_id = p_set_id;
	if not found then
		raise exception 'Slony-I: setAddSequence_int(): set % not found',
				p_set_id;
	end if;
	if v_set_origin != v_local_node_id then
		select sub_provider into v_sub_provider
				from "_primer_cluster2".sl_subscribe
				where sub_set = p_set_id
				and sub_receiver = "_primer_cluster2".getLocalNodeId('_primer_cluster2');
		if not found then
			return 0;
		end if;
	end if;
	
	-- ----
	-- Get the sequences OID and check that it is a sequence
	-- ----
	select PGC.oid, PGC.relkind, PGC.relname, PGN.nspname 
		into v_seq_reloid, v_relkind, v_seq_relname, v_seq_nspname
			from "pg_catalog".pg_class PGC, "pg_catalog".pg_namespace PGN
			where PGC.relnamespace = PGN.oid
			and "_primer_cluster2".slon_quote_input(p_fqname) = "_primer_cluster2".slon_quote_brute(PGN.nspname) ||
					'.' || "_primer_cluster2".slon_quote_brute(PGC.relname);
	if not found then
		raise exception 'Slony-I: setAddSequence_int(): sequence % not found', 
				p_fqname;
	end if;
	if v_relkind != 'S' then
		raise exception 'Slony-I: setAddSequence_int(): % is not a sequence',
				p_fqname;
	end if;

        select 1 into v_sync_row from "_primer_cluster2".sl_sequence where seq_id = p_seq_id;
	if not found then
               v_relkind := 'o';   -- all is OK
        else
                raise exception 'Slony-I: setAddSequence_int(): sequence ID % has already been assigned', p_seq_id;
        end if;

	-- ----
	-- Add the sequence to sl_sequence
	-- ----
	insert into "_primer_cluster2".sl_sequence
		(seq_id, seq_reloid, seq_relname, seq_nspname, seq_set, seq_comment) 
		values
		(p_seq_id, v_seq_reloid, v_seq_relname, v_seq_nspname,  p_set_id, p_seq_comment);

	-- ----
	-- On the set origin, fake a sl_seqlog row for the last sync event
	-- ----
	if v_set_origin = v_local_node_id then
		for v_sync_row in select coalesce (max(ev_seqno), 0) as ev_seqno
				from "_primer_cluster2".sl_event
				where ev_origin = v_local_node_id
					and ev_type = 'SYNC'
		loop
			insert into "_primer_cluster2".sl_seqlog
					(seql_seqid, seql_origin, seql_ev_seqno, 
					seql_last_value) values
					(p_seq_id, v_local_node_id, v_sync_row.ev_seqno,
					"_primer_cluster2".sequenceLastValue(p_fqname));
		end loop;
	end if;

	return p_seq_id;
end;
$$;


ALTER FUNCTION _primer_cluster2.setaddsequence_int(p_set_id integer, p_seq_id integer, p_fqname text, p_seq_comment text) OWNER TO postgres;

--
-- Name: FUNCTION setaddsequence_int(p_set_id integer, p_seq_id integer, p_fqname text, p_seq_comment text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.setaddsequence_int(p_set_id integer, p_seq_id integer, p_fqname text, p_seq_comment text) IS 'setAddSequence_int (set_id, seq_id, seq_fqname, seq_comment)

This processes the SET_ADD_SEQUENCE event.  On remote nodes that
subscribe to set_id, add the sequence to the replication set.';


--
-- Name: setaddtable(integer, integer, text, name, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.setaddtable(p_set_id integer, p_tab_id integer, p_fqname text, p_tab_idxname name, p_tab_comment text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	v_set_origin		int4;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Check that we are the origin of the set
	-- ----
	select set_origin into v_set_origin
			from "_primer_cluster2".sl_set
			where set_id = p_set_id;
	if not found then
		raise exception 'Slony-I: setAddTable(): set % not found', p_set_id;
	end if;
	if v_set_origin != "_primer_cluster2".getLocalNodeId('_primer_cluster2') then
		raise exception 'Slony-I: setAddTable(): set % has remote origin', p_set_id;
	end if;

	if exists (select true from "_primer_cluster2".sl_subscribe
			where sub_set = p_set_id)
	then
		raise exception 'Slony-I: cannot add table to currently subscribed set % - must attach to an unsubscribed set',
				p_set_id;
	end if;

	-- ----
	-- Add the table to the set and generate the SET_ADD_TABLE event
	-- ----
	perform "_primer_cluster2".setAddTable_int(p_set_id, p_tab_id, p_fqname,
			p_tab_idxname, p_tab_comment);
	return  "_primer_cluster2".createEvent('_primer_cluster2', 'SET_ADD_TABLE',
			p_set_id::text, p_tab_id::text, p_fqname::text,
			p_tab_idxname::text, p_tab_comment::text);
end;
$$;


ALTER FUNCTION _primer_cluster2.setaddtable(p_set_id integer, p_tab_id integer, p_fqname text, p_tab_idxname name, p_tab_comment text) OWNER TO postgres;

--
-- Name: FUNCTION setaddtable(p_set_id integer, p_tab_id integer, p_fqname text, p_tab_idxname name, p_tab_comment text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.setaddtable(p_set_id integer, p_tab_id integer, p_fqname text, p_tab_idxname name, p_tab_comment text) IS 'setAddTable (set_id, tab_id, tab_fqname, tab_idxname, tab_comment)

Add table tab_fqname to replication set on origin node, and generate
SET_ADD_TABLE event to allow this to propagate to other nodes.

Note that the table id, tab_id, must be unique ACROSS ALL SETS.';


--
-- Name: setaddtable_int(integer, integer, text, name, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.setaddtable_int(p_set_id integer, p_tab_id integer, p_fqname text, p_tab_idxname name, p_tab_comment text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_tab_relname		name;
	v_tab_nspname		name;
	v_local_node_id		int4;
	v_set_origin		int4;
	v_sub_provider		int4;
	v_relkind		char;
	v_tab_reloid		oid;
	v_pkcand_nn		boolean;
	v_prec			record;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- For sets with a remote origin, check that we are subscribed 
	-- to that set. Otherwise we ignore the table because it might 
	-- not even exist in our database.
	-- ----
	v_local_node_id := "_primer_cluster2".getLocalNodeId('_primer_cluster2');
	select set_origin into v_set_origin
			from "_primer_cluster2".sl_set
			where set_id = p_set_id;
	if not found then
		raise exception 'Slony-I: setAddTable_int(): set % not found',
				p_set_id;
	end if;
	if v_set_origin != v_local_node_id then
		select sub_provider into v_sub_provider
				from "_primer_cluster2".sl_subscribe
				where sub_set = p_set_id
				and sub_receiver = "_primer_cluster2".getLocalNodeId('_primer_cluster2');
		if not found then
			return 0;
		end if;
	end if;
	
	-- ----
	-- Get the tables OID and check that it is a real table
	-- ----
	select PGC.oid, PGC.relkind, PGC.relname, PGN.nspname into v_tab_reloid, v_relkind, v_tab_relname, v_tab_nspname
			from "pg_catalog".pg_class PGC, "pg_catalog".pg_namespace PGN
			where PGC.relnamespace = PGN.oid
			and "_primer_cluster2".slon_quote_input(p_fqname) = "_primer_cluster2".slon_quote_brute(PGN.nspname) ||
					'.' || "_primer_cluster2".slon_quote_brute(PGC.relname);
	if not found then
		raise exception 'Slony-I: setAddTable_int(): table % not found', 
				p_fqname;
	end if;
	if v_relkind != 'r' then
		raise exception 'Slony-I: setAddTable_int(): % is not a regular table',
				p_fqname;
	end if;

	if not exists (select indexrelid
			from "pg_catalog".pg_index PGX, "pg_catalog".pg_class PGC
			where PGX.indrelid = v_tab_reloid
				and PGX.indexrelid = PGC.oid
				and PGC.relname = p_tab_idxname)
	then
		raise exception 'Slony-I: setAddTable_int(): table % has no index %',
				p_fqname, p_tab_idxname;
	end if;

	-- ----
	-- Verify that the columns in the PK (or candidate) are not NULLABLE
	-- ----

	v_pkcand_nn := 'f';
	for v_prec in select attname from "pg_catalog".pg_attribute where attrelid = 
                        (select oid from "pg_catalog".pg_class where oid = v_tab_reloid) 
                    and attname in (select attname from "pg_catalog".pg_attribute where 
                                    attrelid = (select oid from "pg_catalog".pg_class PGC, 
                                    "pg_catalog".pg_index PGX where 
                                    PGC.relname = p_tab_idxname and PGX.indexrelid=PGC.oid and
                                    PGX.indrelid = v_tab_reloid)) and attnotnull <> 't'
	loop
		raise notice 'Slony-I: setAddTable_int: table % PK column % nullable', p_fqname, v_prec.attname;
		v_pkcand_nn := 't';
	end loop;
	if v_pkcand_nn then
		raise exception 'Slony-I: setAddTable_int: table % not replicable!', p_fqname;
	end if;

	select * into v_prec from "_primer_cluster2".sl_table where tab_id = p_tab_id;
	if not found then
		v_pkcand_nn := 't';  -- No-op -- All is well
	else
		raise exception 'Slony-I: setAddTable_int: table id % has already been assigned!', p_tab_id;
	end if;

	-- ----
	-- Add the table to sl_table and create the trigger on it.
	-- ----
	insert into "_primer_cluster2".sl_table
			(tab_id, tab_reloid, tab_relname, tab_nspname, 
			tab_set, tab_idxname, tab_altered, tab_comment) 
			values
			(p_tab_id, v_tab_reloid, v_tab_relname, v_tab_nspname,
			p_set_id, p_tab_idxname, false, p_tab_comment);
	perform "_primer_cluster2".alterTableAddTriggers(p_tab_id);

	return p_tab_id;
end;
$$;


ALTER FUNCTION _primer_cluster2.setaddtable_int(p_set_id integer, p_tab_id integer, p_fqname text, p_tab_idxname name, p_tab_comment text) OWNER TO postgres;

--
-- Name: FUNCTION setaddtable_int(p_set_id integer, p_tab_id integer, p_fqname text, p_tab_idxname name, p_tab_comment text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.setaddtable_int(p_set_id integer, p_tab_id integer, p_fqname text, p_tab_idxname name, p_tab_comment text) IS 'setAddTable_int (set_id, tab_id, tab_fqname, tab_idxname, tab_comment)

This function processes the SET_ADD_TABLE event on remote nodes,
adding a table to replication if the remote node is subscribing to its
replication set.';


--
-- Name: setdropsequence(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.setdropsequence(p_seq_id integer) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	v_set_id		int4;
	v_set_origin		int4;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Determine set id for this sequence
	-- ----
	select seq_set into v_set_id from "_primer_cluster2".sl_sequence where seq_id = p_seq_id;

	-- ----
	-- Ensure sequence exists
	-- ----
	if not found then
		raise exception 'Slony-I: setDropSequence_int(): sequence % not found',
			p_seq_id;
	end if;

	-- ----
	-- Check that we are the origin of the set
	-- ----
	select set_origin into v_set_origin
			from "_primer_cluster2".sl_set
			where set_id = v_set_id;
	if not found then
		raise exception 'Slony-I: setDropSequence(): set % not found', v_set_id;
	end if;
	if v_set_origin != "_primer_cluster2".getLocalNodeId('_primer_cluster2') then
		raise exception 'Slony-I: setDropSequence(): set % has origin at another node - submit this to that node', v_set_id;
	end if;

	-- ----
	-- Add the sequence to the set and generate the SET_ADD_SEQUENCE event
	-- ----
	perform "_primer_cluster2".setDropSequence_int(p_seq_id);
	return  "_primer_cluster2".createEvent('_primer_cluster2', 'SET_DROP_SEQUENCE',
					p_seq_id::text);
end;
$$;


ALTER FUNCTION _primer_cluster2.setdropsequence(p_seq_id integer) OWNER TO postgres;

--
-- Name: FUNCTION setdropsequence(p_seq_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.setdropsequence(p_seq_id integer) IS 'setDropSequence (seq_id)

On the origin node for the set, drop sequence seq_id from replication
set, and raise SET_DROP_SEQUENCE to cause this to replicate to
subscriber nodes.';


--
-- Name: setdropsequence_int(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.setdropsequence_int(p_seq_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_set_id		int4;
	v_local_node_id		int4;
	v_set_origin		int4;
	v_sub_provider		int4;
	v_relkind			char;
	v_sync_row			record;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Determine set id for this sequence
	-- ----
	select seq_set into v_set_id from "_primer_cluster2".sl_sequence where seq_id = p_seq_id;

	-- ----
	-- Ensure sequence exists
	-- ----
	if not found then
		return 0;
	end if;

	-- ----
	-- For sets with a remote origin, check that we are subscribed 
	-- to that set. Otherwise we ignore the sequence because it might 
	-- not even exist in our database.
	-- ----
	v_local_node_id := "_primer_cluster2".getLocalNodeId('_primer_cluster2');
	select set_origin into v_set_origin
			from "_primer_cluster2".sl_set
			where set_id = v_set_id;
	if not found then
		raise exception 'Slony-I: setDropSequence_int(): set % not found',
				v_set_id;
	end if;
	if v_set_origin != v_local_node_id then
		select sub_provider into v_sub_provider
				from "_primer_cluster2".sl_subscribe
				where sub_set = v_set_id
				and sub_receiver = "_primer_cluster2".getLocalNodeId('_primer_cluster2');
		if not found then
			return 0;
		end if;
	end if;

	-- ----
	-- drop the sequence from sl_sequence, sl_seqlog
	-- ----
	delete from "_primer_cluster2".sl_seqlog where seql_seqid = p_seq_id;
	delete from "_primer_cluster2".sl_sequence where seq_id = p_seq_id;

	return p_seq_id;
end;
$$;


ALTER FUNCTION _primer_cluster2.setdropsequence_int(p_seq_id integer) OWNER TO postgres;

--
-- Name: FUNCTION setdropsequence_int(p_seq_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.setdropsequence_int(p_seq_id integer) IS 'setDropSequence_int (seq_id)

This processes the SET_DROP_SEQUENCE event.  On remote nodes that
subscribe to the set containing sequence seq_id, drop the sequence
from the replication set.';


--
-- Name: setdroptable(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.setdroptable(p_tab_id integer) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	v_set_id		int4;
	v_set_origin		int4;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

    -- ----
	-- Determine the set_id
    -- ----
	select tab_set into v_set_id from "_primer_cluster2".sl_table where tab_id = p_tab_id;

	-- ----
	-- Ensure table exists
	-- ----
	if not found then
		raise exception 'Slony-I: setDropTable_int(): table % not found',
			p_tab_id;
	end if;

	-- ----
	-- Check that we are the origin of the set
	-- ----
	select set_origin into v_set_origin
			from "_primer_cluster2".sl_set
			where set_id = v_set_id;
	if not found then
		raise exception 'Slony-I: setDropTable(): set % not found', v_set_id;
	end if;
	if v_set_origin != "_primer_cluster2".getLocalNodeId('_primer_cluster2') then
		raise exception 'Slony-I: setDropTable(): set % has remote origin', v_set_id;
	end if;

	-- ----
	-- Drop the table from the set and generate the SET_ADD_TABLE event
	-- ----
	perform "_primer_cluster2".setDropTable_int(p_tab_id);
	return  "_primer_cluster2".createEvent('_primer_cluster2', 'SET_DROP_TABLE', 
				p_tab_id::text);
end;
$$;


ALTER FUNCTION _primer_cluster2.setdroptable(p_tab_id integer) OWNER TO postgres;

--
-- Name: FUNCTION setdroptable(p_tab_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.setdroptable(p_tab_id integer) IS 'setDropTable (tab_id)

Drop table tab_id from set on origin node, and generate SET_DROP_TABLE
event to allow this to propagate to other nodes.';


--
-- Name: setdroptable_int(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.setdroptable_int(p_tab_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_set_id		int4;
	v_local_node_id		int4;
	v_set_origin		int4;
	v_sub_provider		int4;
	v_tab_reloid		oid;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

    -- ----
	-- Determine the set_id
    -- ----
	select tab_set into v_set_id from "_primer_cluster2".sl_table where tab_id = p_tab_id;

	-- ----
	-- Ensure table exists
	-- ----
	if not found then
		return 0;
	end if;

	-- ----
	-- For sets with a remote origin, check that we are subscribed 
	-- to that set. Otherwise we ignore the table because it might 
	-- not even exist in our database.
	-- ----
	v_local_node_id := "_primer_cluster2".getLocalNodeId('_primer_cluster2');
	select set_origin into v_set_origin
			from "_primer_cluster2".sl_set
			where set_id = v_set_id;
	if not found then
		raise exception 'Slony-I: setDropTable_int(): set % not found',
				v_set_id;
	end if;
	if v_set_origin != v_local_node_id then
		select sub_provider into v_sub_provider
				from "_primer_cluster2".sl_subscribe
				where sub_set = v_set_id
				and sub_receiver = "_primer_cluster2".getLocalNodeId('_primer_cluster2');
		if not found then
			return 0;
		end if;
	end if;
	
	-- ----
	-- Drop the table from sl_table and drop trigger from it.
	-- ----
	perform "_primer_cluster2".alterTableDropTriggers(p_tab_id);
	delete from "_primer_cluster2".sl_table where tab_id = p_tab_id;
	return p_tab_id;
end;
$$;


ALTER FUNCTION _primer_cluster2.setdroptable_int(p_tab_id integer) OWNER TO postgres;

--
-- Name: FUNCTION setdroptable_int(p_tab_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.setdroptable_int(p_tab_id integer) IS 'setDropTable_int (tab_id)

This function processes the SET_DROP_TABLE event on remote nodes,
dropping a table from replication if the remote node is subscribing to
its replication set.';


--
-- Name: setmovesequence(integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.setmovesequence(p_seq_id integer, p_new_set_id integer) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	v_old_set_id		int4;
	v_origin			int4;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Get the sequences current set
	-- ----
	select seq_set into v_old_set_id from "_primer_cluster2".sl_sequence
			where seq_id = p_seq_id;
	if not found then
		raise exception 'Slony-I: setMoveSequence(): sequence %d not found', p_seq_id;
	end if;
	
	-- ----
	-- Check that both sets exist and originate here
	-- ----
	if p_new_set_id = v_old_set_id then
		raise exception 'Slony-I: setMoveSequence(): set ids cannot be identical';
	end if;
	select set_origin into v_origin from "_primer_cluster2".sl_set
			where set_id = p_new_set_id;
	if not found then
		raise exception 'Slony-I: setMoveSequence(): set % not found', p_new_set_id;
	end if;
	if v_origin != "_primer_cluster2".getLocalNodeId('_primer_cluster2') then
		raise exception 'Slony-I: setMoveSequence(): set % does not originate on local node',
				p_new_set_id;
	end if;

	select set_origin into v_origin from "_primer_cluster2".sl_set
			where set_id = v_old_set_id;
	if not found then
		raise exception 'Slony-I: set % not found', v_old_set_id;
	end if;
	if v_origin != "_primer_cluster2".getLocalNodeId('_primer_cluster2') then
		raise exception 'Slony-I: set % does not originate on local node',
				v_old_set_id;
	end if;

	-- ----
	-- Check that both sets are subscribed by the same set of nodes
	-- ----
	if exists (select true from "_primer_cluster2".sl_subscribe SUB1
				where SUB1.sub_set = p_new_set_id
				and SUB1.sub_receiver not in (select SUB2.sub_receiver
						from "_primer_cluster2".sl_subscribe SUB2
						where SUB2.sub_set = v_old_set_id))
	then
		raise exception 'Slony-I: subscriber lists of set % and % are different',
				p_new_set_id, v_old_set_id;
	end if;

	if exists (select true from "_primer_cluster2".sl_subscribe SUB1
				where SUB1.sub_set = v_old_set_id
				and SUB1.sub_receiver not in (select SUB2.sub_receiver
						from "_primer_cluster2".sl_subscribe SUB2
						where SUB2.sub_set = p_new_set_id))
	then
		raise exception 'Slony-I: subscriber lists of set % and % are different',
				v_old_set_id, p_new_set_id;
	end if;

	-- ----
	-- Change the set the sequence belongs to
	-- ----
	perform "_primer_cluster2".setMoveSequence_int(p_seq_id, p_new_set_id);
	return  "_primer_cluster2".createEvent('_primer_cluster2', 'SET_MOVE_SEQUENCE', 
			p_seq_id::text, p_new_set_id::text);
end;
$$;


ALTER FUNCTION _primer_cluster2.setmovesequence(p_seq_id integer, p_new_set_id integer) OWNER TO postgres;

--
-- Name: FUNCTION setmovesequence(p_seq_id integer, p_new_set_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.setmovesequence(p_seq_id integer, p_new_set_id integer) IS 'setMoveSequence(p_seq_id, p_new_set_id) - This generates the
SET_MOVE_SEQUENCE event, after validation, notably that both sets
exist, are distinct, and have exactly the same subscription lists';


--
-- Name: setmovesequence_int(integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.setmovesequence_int(p_seq_id integer, p_new_set_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Move the sequence to the new set
	-- ----
	update "_primer_cluster2".sl_sequence
			set seq_set = p_new_set_id
			where seq_id = p_seq_id;

	return p_seq_id;
end;
$$;


ALTER FUNCTION _primer_cluster2.setmovesequence_int(p_seq_id integer, p_new_set_id integer) OWNER TO postgres;

--
-- Name: FUNCTION setmovesequence_int(p_seq_id integer, p_new_set_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.setmovesequence_int(p_seq_id integer, p_new_set_id integer) IS 'setMoveSequence_int(p_seq_id, p_new_set_id) - processes the
SET_MOVE_SEQUENCE event, moving a sequence to another replication
set.';


--
-- Name: setmovetable(integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.setmovetable(p_tab_id integer, p_new_set_id integer) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	v_old_set_id		int4;
	v_origin			int4;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Get the tables current set
	-- ----
	select tab_set into v_old_set_id from "_primer_cluster2".sl_table
			where tab_id = p_tab_id;
	if not found then
		raise exception 'Slony-I: table %d not found', p_tab_id;
	end if;
	
	-- ----
	-- Check that both sets exist and originate here
	-- ----
	if p_new_set_id = v_old_set_id then
		raise exception 'Slony-I: set ids cannot be identical';
	end if;
	select set_origin into v_origin from "_primer_cluster2".sl_set
			where set_id = p_new_set_id;
	if not found then
		raise exception 'Slony-I: set % not found', p_new_set_id;
	end if;
	if v_origin != "_primer_cluster2".getLocalNodeId('_primer_cluster2') then
		raise exception 'Slony-I: set % does not originate on local node',
				p_new_set_id;
	end if;

	select set_origin into v_origin from "_primer_cluster2".sl_set
			where set_id = v_old_set_id;
	if not found then
		raise exception 'Slony-I: set % not found', v_old_set_id;
	end if;
	if v_origin != "_primer_cluster2".getLocalNodeId('_primer_cluster2') then
		raise exception 'Slony-I: set % does not originate on local node',
				v_old_set_id;
	end if;

	-- ----
	-- Check that both sets are subscribed by the same set of nodes
	-- ----
	if exists (select true from "_primer_cluster2".sl_subscribe SUB1
				where SUB1.sub_set = p_new_set_id
				and SUB1.sub_receiver not in (select SUB2.sub_receiver
						from "_primer_cluster2".sl_subscribe SUB2
						where SUB2.sub_set = v_old_set_id))
	then
		raise exception 'Slony-I: subscriber lists of set % and % are different',
				p_new_set_id, v_old_set_id;
	end if;

	if exists (select true from "_primer_cluster2".sl_subscribe SUB1
				where SUB1.sub_set = v_old_set_id
				and SUB1.sub_receiver not in (select SUB2.sub_receiver
						from "_primer_cluster2".sl_subscribe SUB2
						where SUB2.sub_set = p_new_set_id))
	then
		raise exception 'Slony-I: subscriber lists of set % and % are different',
				v_old_set_id, p_new_set_id;
	end if;

	-- ----
	-- Change the set the table belongs to
	-- ----
	perform "_primer_cluster2".createEvent('_primer_cluster2', 'SYNC', NULL);
	perform "_primer_cluster2".setMoveTable_int(p_tab_id, p_new_set_id);
	return  "_primer_cluster2".createEvent('_primer_cluster2', 'SET_MOVE_TABLE', 
			p_tab_id::text, p_new_set_id::text);
end;
$$;


ALTER FUNCTION _primer_cluster2.setmovetable(p_tab_id integer, p_new_set_id integer) OWNER TO postgres;

--
-- Name: FUNCTION setmovetable(p_tab_id integer, p_new_set_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.setmovetable(p_tab_id integer, p_new_set_id integer) IS 'This processes the SET_MOVE_TABLE event.  The table is moved 
to the destination set.';


--
-- Name: setmovetable_int(integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.setmovetable_int(p_tab_id integer, p_new_set_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Move the table to the new set
	-- ----
	update "_primer_cluster2".sl_table
			set tab_set = p_new_set_id
			where tab_id = p_tab_id;

	return p_tab_id;
end;
$$;


ALTER FUNCTION _primer_cluster2.setmovetable_int(p_tab_id integer, p_new_set_id integer) OWNER TO postgres;

--
-- Name: shouldslonyvacuumtable(name, name); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.shouldslonyvacuumtable(i_nspname name, i_tblname name) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
declare
	c_table oid;
	c_namespace oid;
	c_enabled boolean;
	v_dummy int4;
begin
	if not exists (select 1 from pg_catalog.pg_class c, pg_catalog.pg_namespace n 
                   where c.relname = i_tblname and n.nspname = i_nspname and c.relnamespace = n.oid) then
        return 'f'::boolean;   -- if table does not exist, then don't vacuum
	end if;				
	select 1 into v_dummy from "pg_catalog".pg_settings where name = 'autovacuum' and setting = 'on';
	if not found then
		return 't'::boolean;       -- If autovac is turned off, then we gotta vacuum
	end if;
	
	select into c_namespace oid from "pg_catalog".pg_namespace where nspname = i_nspname;
	if not found then
		raise exception 'Slony-I: namespace % does not exist', i_nspname;
	end if;
	select into c_table oid from "pg_catalog".pg_class where relname = i_tblname and relnamespace = c_namespace;
	if not found then
		raise warning 'Slony-I: table % does not exist in namespace %/%', i_tblname, c_namespace, i_nspname;
		return 'f'::boolean;
	end if;
	
	-- So, the table is legit; try to look it up for autovacuum policy
	if exists (select 1 from pg_class where 'autovacuum_enabled=off' = any (reloptions) and oid = c_table) then
		return 't'::boolean;   -- Autovac is turned on, but this table is disabled
	end if;

	return 'f'::boolean;

end;$$;


ALTER FUNCTION _primer_cluster2.shouldslonyvacuumtable(i_nspname name, i_tblname name) OWNER TO postgres;

--
-- Name: FUNCTION shouldslonyvacuumtable(i_nspname name, i_tblname name); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.shouldslonyvacuumtable(i_nspname name, i_tblname name) IS 'returns false if autovacuum handles vacuuming of the table, or if the table does not exist; returns true if Slony-I should manage it';


--
-- Name: slon_node_health_check(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.slon_node_health_check() RETURNS boolean
    LANGUAGE plpgsql
    AS $$
declare
		prec record;
		all_ok boolean;
begin
		all_ok := 't'::boolean;
		-- validate that all tables in sl_table have:
		--      sl_table agreeing with pg_class
		for prec in select tab_id, tab_relname, tab_nspname from
		"_primer_cluster2".sl_table t where not exists (select 1 from pg_catalog.pg_class c, pg_catalog.pg_namespace n
				where c.oid = t.tab_reloid and c.relname = t.tab_relname and c.relnamespace = n.oid and n.nspname = t.tab_nspname) loop
				all_ok := 'f'::boolean;
				raise warning 'table [id,nsp,name]=[%,%,%] - sl_table does not match pg_class/pg_namespace', prec.tab_id, prec.tab_relname, prec.tab_nspname;
		end loop;
		if not all_ok then
		   raise warning 'Mismatch found between sl_table and pg_class.  Slonik command REPAIR CONFIG may be useful to rectify this.';
		end if;
		return all_ok;
end
$$;


ALTER FUNCTION _primer_cluster2.slon_node_health_check() OWNER TO postgres;

--
-- Name: FUNCTION slon_node_health_check(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.slon_node_health_check() IS 'called when slon starts up to validate that there are not problems with node configuration.  Returns t if all is OK, f if there is a problem.';


--
-- Name: slon_quote_brute(text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.slon_quote_brute(p_tab_fqname text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare	
    v_fqname text default '';
begin
    v_fqname := '"' || replace(p_tab_fqname,'"','""') || '"';
    return v_fqname;
end;
$$;


ALTER FUNCTION _primer_cluster2.slon_quote_brute(p_tab_fqname text) OWNER TO postgres;

--
-- Name: FUNCTION slon_quote_brute(p_tab_fqname text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.slon_quote_brute(p_tab_fqname text) IS 'Brutally quote the given text';


--
-- Name: slon_quote_input(text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.slon_quote_input(p_tab_fqname text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
  declare
     v_nsp_name text;
     v_tab_name text;
	 v_i integer;
	 v_l integer;
     v_pq2 integer;
begin
	v_l := length(p_tab_fqname);

	-- Let us search for the dot
	if p_tab_fqname like '"%' then
		-- if the first part of the ident starts with a double quote, search
		-- for the closing double quote, skipping over double double quotes.
		v_i := 2;
		while v_i <= v_l loop
			if substr(p_tab_fqname, v_i, 1) != '"' then
				v_i := v_i + 1;
			else
				v_i := v_i + 1;
				if substr(p_tab_fqname, v_i, 1) != '"' then
					exit;
				end if;
				v_i := v_i + 1;
			end if;
		end loop;
	else
		-- first part of ident is not quoted, search for the dot directly
		v_i := 1;
		while v_i <= v_l loop
			if substr(p_tab_fqname, v_i, 1) = '.' then
				exit;
			end if;
			v_i := v_i + 1;
		end loop;
	end if;

	-- v_i now points at the dot or behind the string.

	if substr(p_tab_fqname, v_i, 1) = '.' then
		-- There is a dot now, so split the ident into its namespace
		-- and objname parts and make sure each is quoted
		v_nsp_name := substr(p_tab_fqname, 1, v_i - 1);
		v_tab_name := substr(p_tab_fqname, v_i + 1);
		if v_nsp_name not like '"%' then
			v_nsp_name := '"' || replace(v_nsp_name, '"', '""') ||
						  '"';
		end if;
		if v_tab_name not like '"%' then
			v_tab_name := '"' || replace(v_tab_name, '"', '""') ||
						  '"';
		end if;

		return v_nsp_name || '.' || v_tab_name;
	else
		-- No dot ... must be just an ident without schema
		if p_tab_fqname like '"%' then
			return p_tab_fqname;
		else
			return '"' || replace(p_tab_fqname, '"', '""') || '"';
		end if;
	end if;

end;$$;


ALTER FUNCTION _primer_cluster2.slon_quote_input(p_tab_fqname text) OWNER TO postgres;

--
-- Name: FUNCTION slon_quote_input(p_tab_fqname text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.slon_quote_input(p_tab_fqname text) IS 'quote all words that aren''t quoted yet';


--
-- Name: slonyversion(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.slonyversion() RETURNS text
    LANGUAGE plpgsql
    AS $$
begin
	return "_primer_cluster2".slonyVersionMajor()::text || '.' || 
	       "_primer_cluster2".slonyVersionMinor()::text || '.' || 
	       "_primer_cluster2".slonyVersionPatchlevel()::text   ;
end;
$$;


ALTER FUNCTION _primer_cluster2.slonyversion() OWNER TO postgres;

--
-- Name: FUNCTION slonyversion(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.slonyversion() IS 'Returns the version number of the slony schema';


--
-- Name: slonyversionmajor(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.slonyversionmajor() RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
	return 2;
end;
$$;


ALTER FUNCTION _primer_cluster2.slonyversionmajor() OWNER TO postgres;

--
-- Name: FUNCTION slonyversionmajor(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.slonyversionmajor() IS 'Returns the major version number of the slony schema';


--
-- Name: slonyversionminor(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.slonyversionminor() RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
	return 2;
end;
$$;


ALTER FUNCTION _primer_cluster2.slonyversionminor() OWNER TO postgres;

--
-- Name: FUNCTION slonyversionminor(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.slonyversionminor() IS 'Returns the minor version number of the slony schema';


--
-- Name: slonyversionpatchlevel(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.slonyversionpatchlevel() RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
	return 6;
end;
$$;


ALTER FUNCTION _primer_cluster2.slonyversionpatchlevel() OWNER TO postgres;

--
-- Name: FUNCTION slonyversionpatchlevel(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.slonyversionpatchlevel() IS 'Returns the version patch level of the slony schema';


--
-- Name: store_application_name(text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.store_application_name(i_name text) RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
		p_command text;
begin
		if exists (select 1 from pg_catalog.pg_settings where name = 'application_name') then
		   p_command := 'set application_name to '''|| i_name || ''';';
		   execute p_command;
		   return i_name;
		end if;
		return NULL::text;
end $$;


ALTER FUNCTION _primer_cluster2.store_application_name(i_name text) OWNER TO postgres;

--
-- Name: FUNCTION store_application_name(i_name text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.store_application_name(i_name text) IS 'Set application_name GUC, if possible.  Returns NULL if it fails to work.';


--
-- Name: storelisten(integer, integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.storelisten(p_origin integer, p_provider integer, p_receiver integer) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
begin
	perform "_primer_cluster2".storeListen_int (p_origin, p_provider, p_receiver);
	return  "_primer_cluster2".createEvent ('_primer_cluster2', 'STORE_LISTEN',
			p_origin::text, p_provider::text, p_receiver::text);
end;
$$;


ALTER FUNCTION _primer_cluster2.storelisten(p_origin integer, p_provider integer, p_receiver integer) OWNER TO postgres;

--
-- Name: FUNCTION storelisten(p_origin integer, p_provider integer, p_receiver integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.storelisten(p_origin integer, p_provider integer, p_receiver integer) IS 'FUNCTION storeListen (li_origin, li_provider, li_receiver)

generate STORE_LISTEN event, indicating that receiver node li_receiver
listens to node li_provider in order to get messages coming from node
li_origin.';


--
-- Name: storelisten_int(integer, integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.storelisten_int(p_li_origin integer, p_li_provider integer, p_li_receiver integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_exists		int4;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	select 1 into v_exists
			from "_primer_cluster2".sl_listen
			where li_origin = p_li_origin
			and li_provider = p_li_provider
			and li_receiver = p_li_receiver;
	if not found then
		-- ----
		-- In case we receive STORE_LISTEN events before we know
		-- about the nodes involved in this, we generate those nodes
		-- as pending.
		-- ----
		if not exists (select 1 from "_primer_cluster2".sl_node
						where no_id = p_li_origin) then
			perform "_primer_cluster2".storeNode_int (p_li_origin, '<event pending>');
		end if;
		if not exists (select 1 from "_primer_cluster2".sl_node
						where no_id = p_li_provider) then
			perform "_primer_cluster2".storeNode_int (p_li_provider, '<event pending>');
		end if;
		if not exists (select 1 from "_primer_cluster2".sl_node
						where no_id = p_li_receiver) then
			perform "_primer_cluster2".storeNode_int (p_li_receiver, '<event pending>');
		end if;

		insert into "_primer_cluster2".sl_listen
				(li_origin, li_provider, li_receiver) values
				(p_li_origin, p_li_provider, p_li_receiver);
	end if;

	return 0;
end;
$$;


ALTER FUNCTION _primer_cluster2.storelisten_int(p_li_origin integer, p_li_provider integer, p_li_receiver integer) OWNER TO postgres;

--
-- Name: FUNCTION storelisten_int(p_li_origin integer, p_li_provider integer, p_li_receiver integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.storelisten_int(p_li_origin integer, p_li_provider integer, p_li_receiver integer) IS 'FUNCTION storeListen_int (li_origin, li_provider, li_receiver)

Process STORE_LISTEN event, indicating that receiver node li_receiver
listens to node li_provider in order to get messages coming from node
li_origin.';


--
-- Name: storenode(integer, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.storenode(p_no_id integer, p_no_comment text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
begin
	perform "_primer_cluster2".storeNode_int (p_no_id, p_no_comment);
	return  "_primer_cluster2".createEvent('_primer_cluster2', 'STORE_NODE',
									p_no_id::text, p_no_comment::text);
end;
$$;


ALTER FUNCTION _primer_cluster2.storenode(p_no_id integer, p_no_comment text) OWNER TO postgres;

--
-- Name: FUNCTION storenode(p_no_id integer, p_no_comment text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.storenode(p_no_id integer, p_no_comment text) IS 'no_id - Node ID #
no_comment - Human-oriented comment

Generate the STORE_NODE event for node no_id';


--
-- Name: storenode_int(integer, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.storenode_int(p_no_id integer, p_no_comment text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_old_row		record;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Check if the node exists
	-- ----
	select * into v_old_row
			from "_primer_cluster2".sl_node
			where no_id = p_no_id
			for update;
	if found then 
		-- ----
		-- Node exists, update the existing row.
		-- ----
		update "_primer_cluster2".sl_node
				set no_comment = p_no_comment
				where no_id = p_no_id;
	else
		-- ----
		-- New node, insert the sl_node row
		-- ----
		insert into "_primer_cluster2".sl_node
				(no_id, no_active, no_comment,no_failed) values
				(p_no_id, 'f', p_no_comment,false);
	end if;

	return p_no_id;
end;
$$;


ALTER FUNCTION _primer_cluster2.storenode_int(p_no_id integer, p_no_comment text) OWNER TO postgres;

--
-- Name: FUNCTION storenode_int(p_no_id integer, p_no_comment text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.storenode_int(p_no_id integer, p_no_comment text) IS 'no_id - Node ID #
no_comment - Human-oriented comment

Internal function to process the STORE_NODE event for node no_id';


--
-- Name: storepath(integer, integer, text, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.storepath(p_pa_server integer, p_pa_client integer, p_pa_conninfo text, p_pa_connretry integer) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
begin
	perform "_primer_cluster2".storePath_int(p_pa_server, p_pa_client,
			p_pa_conninfo, p_pa_connretry);
	return  "_primer_cluster2".createEvent('_primer_cluster2', 'STORE_PATH', 
			p_pa_server::text, p_pa_client::text, 
			p_pa_conninfo::text, p_pa_connretry::text);
end;
$$;


ALTER FUNCTION _primer_cluster2.storepath(p_pa_server integer, p_pa_client integer, p_pa_conninfo text, p_pa_connretry integer) OWNER TO postgres;

--
-- Name: FUNCTION storepath(p_pa_server integer, p_pa_client integer, p_pa_conninfo text, p_pa_connretry integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.storepath(p_pa_server integer, p_pa_client integer, p_pa_conninfo text, p_pa_connretry integer) IS 'FUNCTION storePath (pa_server, pa_client, pa_conninfo, pa_connretry)

Generate the STORE_PATH event indicating that node pa_client can
access node pa_server using DSN pa_conninfo';


--
-- Name: storepath_int(integer, integer, text, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.storepath_int(p_pa_server integer, p_pa_client integer, p_pa_conninfo text, p_pa_connretry integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_dummy			int4;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Check if the path already exists
	-- ----
	select 1 into v_dummy
			from "_primer_cluster2".sl_path
			where pa_server = p_pa_server
			and pa_client = p_pa_client
			for update;
	if found then
		-- ----
		-- Path exists, update pa_conninfo
		-- ----
		update "_primer_cluster2".sl_path
				set pa_conninfo = p_pa_conninfo,
					pa_connretry = p_pa_connretry
				where pa_server = p_pa_server
				and pa_client = p_pa_client;
	else
		-- ----
		-- New path
		--
		-- In case we receive STORE_PATH events before we know
		-- about the nodes involved in this, we generate those nodes
		-- as pending.
		-- ----
		if not exists (select 1 from "_primer_cluster2".sl_node
						where no_id = p_pa_server) then
			perform "_primer_cluster2".storeNode_int (p_pa_server, '<event pending>');
		end if;
		if not exists (select 1 from "_primer_cluster2".sl_node
						where no_id = p_pa_client) then
			perform "_primer_cluster2".storeNode_int (p_pa_client, '<event pending>');
		end if;
		insert into "_primer_cluster2".sl_path
				(pa_server, pa_client, pa_conninfo, pa_connretry) values
				(p_pa_server, p_pa_client, p_pa_conninfo, p_pa_connretry);
	end if;

	-- Rewrite sl_listen table
	perform "_primer_cluster2".RebuildListenEntries();

	return 0;
end;
$$;


ALTER FUNCTION _primer_cluster2.storepath_int(p_pa_server integer, p_pa_client integer, p_pa_conninfo text, p_pa_connretry integer) OWNER TO postgres;

--
-- Name: FUNCTION storepath_int(p_pa_server integer, p_pa_client integer, p_pa_conninfo text, p_pa_connretry integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.storepath_int(p_pa_server integer, p_pa_client integer, p_pa_conninfo text, p_pa_connretry integer) IS 'FUNCTION storePath (pa_server, pa_client, pa_conninfo, pa_connretry)

Process the STORE_PATH event indicating that node pa_client can
access node pa_server using DSN pa_conninfo';


--
-- Name: storeset(integer, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.storeset(p_set_id integer, p_set_comment text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	v_local_node_id		int4;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	v_local_node_id := "_primer_cluster2".getLocalNodeId('_primer_cluster2');

	insert into "_primer_cluster2".sl_set
			(set_id, set_origin, set_comment) values
			(p_set_id, v_local_node_id, p_set_comment);

	return "_primer_cluster2".createEvent('_primer_cluster2', 'STORE_SET', 
			p_set_id::text, v_local_node_id::text, p_set_comment::text);
end;
$$;


ALTER FUNCTION _primer_cluster2.storeset(p_set_id integer, p_set_comment text) OWNER TO postgres;

--
-- Name: FUNCTION storeset(p_set_id integer, p_set_comment text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.storeset(p_set_id integer, p_set_comment text) IS 'Generate STORE_SET event for set set_id with human readable comment set_comment';


--
-- Name: storeset_int(integer, integer, text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.storeset_int(p_set_id integer, p_set_origin integer, p_set_comment text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_dummy				int4;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	select 1 into v_dummy
			from "_primer_cluster2".sl_set
			where set_id = p_set_id
			for update;
	if found then 
		update "_primer_cluster2".sl_set
				set set_comment = p_set_comment
				where set_id = p_set_id;
	else
		if not exists (select 1 from "_primer_cluster2".sl_node
						where no_id = p_set_origin) then
			perform "_primer_cluster2".storeNode_int (p_set_origin, '<event pending>');
		end if;
		insert into "_primer_cluster2".sl_set
				(set_id, set_origin, set_comment) values
				(p_set_id, p_set_origin, p_set_comment);
	end if;

	-- Run addPartialLogIndices() to try to add indices to unused sl_log_? table
	perform "_primer_cluster2".addPartialLogIndices();

	return p_set_id;
end;
$$;


ALTER FUNCTION _primer_cluster2.storeset_int(p_set_id integer, p_set_origin integer, p_set_comment text) OWNER TO postgres;

--
-- Name: FUNCTION storeset_int(p_set_id integer, p_set_origin integer, p_set_comment text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.storeset_int(p_set_id integer, p_set_origin integer, p_set_comment text) IS 'storeSet_int (set_id, set_origin, set_comment)

Process the STORE_SET event, indicating the new set with given ID,
origin node, and human readable comment.';


--
-- Name: subscribeset(integer, integer, integer, boolean, boolean); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.subscribeset(p_sub_set integer, p_sub_provider integer, p_sub_receiver integer, p_sub_forward boolean, p_omit_copy boolean) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	v_set_origin		int4;
	v_ev_seqno			int8;
	v_ev_seqno2			int8;
	v_rec			record;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	--
	-- Check that the receiver exists
	--
	if not exists (select no_id from "_primer_cluster2".sl_node where no_id=
	       	      p_sub_receiver) then
		      raise exception 'Slony-I: subscribeSet() receiver % does not exist' , p_sub_receiver;
	end if;

	--
	-- Check that the provider exists
	--
	if not exists (select no_id from "_primer_cluster2".sl_node where no_id=
	       	      p_sub_provider) then
		      raise exception 'Slony-I: subscribeSet() provider % does not exist' , p_sub_provider;
	end if;

	-- ----
	-- Check that the origin and provider of the set are remote
	-- ----
	select set_origin into v_set_origin
			from "_primer_cluster2".sl_set
			where set_id = p_sub_set;
	if not found then
		raise exception 'Slony-I: subscribeSet(): set % not found', p_sub_set;
	end if;
	if v_set_origin = p_sub_receiver then
		raise exception 
				'Slony-I: subscribeSet(): set origin and receiver cannot be identical';
	end if;
	if p_sub_receiver = p_sub_provider then
		raise exception 
				'Slony-I: subscribeSet(): set provider and receiver cannot be identical';
	end if;
	-- ----
	-- Check that this is called on the origin node
	-- ----
	if v_set_origin != "_primer_cluster2".getLocalNodeId('_primer_cluster2') then
		raise exception 'Slony-I: subscribeSet() must be called on origin';
	end if;

	-- ---
	-- Verify that the provider is either the origin or an active subscriber
	-- Bug report #1362
	-- ---
	if v_set_origin <> p_sub_provider then
		if not exists (select 1 from "_primer_cluster2".sl_subscribe
			where sub_set = p_sub_set and 
                              sub_receiver = p_sub_provider and
			      sub_forward and sub_active) then
			raise exception 'Slony-I: subscribeSet(): provider % is not an active forwarding node for replication set %', p_sub_provider, p_sub_set;
		end if;
	end if;

	-- ---
	-- Enforce that all sets from one origin are subscribed
	-- using the same data provider per receiver.
	-- ----
	if not exists (select 1 from "_primer_cluster2".sl_subscribe
			where sub_set = p_sub_set and sub_receiver = p_sub_receiver) then
		--
		-- New subscription - error out if we have any other subscription
		-- from that origin with a different data provider.
		--
		for v_rec in select sub_provider from "_primer_cluster2".sl_subscribe
				join "_primer_cluster2".sl_set on set_id = sub_set
				where set_origin = v_set_origin and sub_receiver = p_sub_receiver
		loop
			if v_rec.sub_provider <> p_sub_provider then
				raise exception 'Slony-I: subscribeSet(): wrong provider % - existing subscription from origin % users provider %',
					p_sub_provider, v_set_origin, v_rec.sub_provider;
			end if;
		end loop;
	else
		--
		-- Existing subscription - in case the data provider changes and
		-- there are other subscriptions, warn here. subscribeSet_int()
		-- will currently change the data provider for those sets as well.
		--
		for v_rec in select set_id, sub_provider from "_primer_cluster2".sl_subscribe
				join "_primer_cluster2".sl_set on set_id = sub_set
				where set_origin = v_set_origin and sub_receiver = p_sub_receiver
				and set_id <> p_sub_set
		loop
			if v_rec.sub_provider <> p_sub_provider then
				raise exception 'Slony-I: subscribeSet(): also data provider for set % use resubscribe instead',
					v_rec.set_id;
			end if;
		end loop;
	end if;

	-- ----
	-- Create the SUBSCRIBE_SET event
	-- ----
	v_ev_seqno :=  "_primer_cluster2".createEvent('_primer_cluster2', 'SUBSCRIBE_SET', 
			p_sub_set::text, p_sub_provider::text, p_sub_receiver::text, 
			case p_sub_forward when true then 't' else 'f' end,
			case p_omit_copy when true then 't' else 'f' end
                        );

	-- ----
	-- Call the internal procedure to store the subscription
	-- ----
	v_ev_seqno2:="_primer_cluster2".subscribeSet_int(p_sub_set, p_sub_provider,
			p_sub_receiver, p_sub_forward, p_omit_copy);
	
	if v_ev_seqno2 is not null then
	   v_ev_seqno:=v_ev_seqno2;
	 end if;

	return v_ev_seqno;
end;
$$;


ALTER FUNCTION _primer_cluster2.subscribeset(p_sub_set integer, p_sub_provider integer, p_sub_receiver integer, p_sub_forward boolean, p_omit_copy boolean) OWNER TO postgres;

--
-- Name: FUNCTION subscribeset(p_sub_set integer, p_sub_provider integer, p_sub_receiver integer, p_sub_forward boolean, p_omit_copy boolean); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.subscribeset(p_sub_set integer, p_sub_provider integer, p_sub_receiver integer, p_sub_forward boolean, p_omit_copy boolean) IS 'subscribeSet (sub_set, sub_provider, sub_receiver, sub_forward, omit_copy)

Makes sure that the receiver is not the provider, then stores the
subscription, and publishes the SUBSCRIBE_SET event to other nodes.

If omit_copy is true, then no data copy will be done.
';


--
-- Name: subscribeset_int(integer, integer, integer, boolean, boolean); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.subscribeset_int(p_sub_set integer, p_sub_provider integer, p_sub_receiver integer, p_sub_forward boolean, p_omit_copy boolean) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_set_origin		int4;
	v_sub_row			record;
	v_seq_id			bigint;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Lookup the set origin
	-- ----
	select set_origin into v_set_origin
			from "_primer_cluster2".sl_set
			where set_id = p_sub_set;
	if not found then
		raise exception 'Slony-I: subscribeSet_int(): set % not found', p_sub_set;
	end if;

	-- ----
	-- Provider change is only allowed for active sets
	-- ----
	if p_sub_receiver = "_primer_cluster2".getLocalNodeId('_primer_cluster2') then
		select sub_active into v_sub_row from "_primer_cluster2".sl_subscribe
				where sub_set = p_sub_set
				and sub_receiver = p_sub_receiver;
		if found then
			if not v_sub_row.sub_active then
				raise exception 'Slony-I: subscribeSet_int(): set % is not active, cannot change provider',
						p_sub_set;
			end if;
		end if;
	end if;

	-- ----
	-- Try to change provider and/or forward for an existing subscription
	-- ----
	update "_primer_cluster2".sl_subscribe
			set sub_provider = p_sub_provider,
				sub_forward = p_sub_forward
			where sub_set = p_sub_set
			and sub_receiver = p_sub_receiver;
	if found then
	  
		-- ----
		-- This is changing a subscriptoin. Make sure all sets from
		-- this origin are subscribed using the same data provider.
		-- For this we first check that the requested data provider
		-- is subscribed to all the sets, the receiver is subscribed to.
		-- ----
		for v_sub_row in select set_id from "_primer_cluster2".sl_set
				join "_primer_cluster2".sl_subscribe on set_id = sub_set
				where set_origin = v_set_origin
				and sub_receiver = p_sub_receiver
				and sub_set <> p_sub_set
		loop
			if not exists (select 1 from "_primer_cluster2".sl_subscribe
					where sub_set = v_sub_row.set_id
					and sub_receiver = p_sub_provider
					and sub_active and sub_forward)
				and not exists (select 1 from "_primer_cluster2".sl_set
					where set_id = v_sub_row.set_id
					and set_origin = p_sub_provider)
			then
				raise exception 'Slony-I: subscribeSet_int(): node % is not a forwarding subscriber for set %',
						p_sub_provider, v_sub_row.set_id;
			end if;

			-- ----
			-- New data provider offers this set as well, change that
			-- subscription too.
			-- ----
			update "_primer_cluster2".sl_subscribe
					set sub_provider = p_sub_provider
					where sub_set = v_sub_row.set_id
					and sub_receiver = p_sub_receiver;
		end loop;

		-- ----
		-- Rewrite sl_listen table
		-- ----
		perform "_primer_cluster2".RebuildListenEntries();

		return p_sub_set;
	end if;

	-- ----
	-- Not found, insert a new one
	-- ----
	if not exists (select true from "_primer_cluster2".sl_path
			where pa_server = p_sub_provider
			and pa_client = p_sub_receiver)
	then
		insert into "_primer_cluster2".sl_path
				(pa_server, pa_client, pa_conninfo, pa_connretry)
				values 
				(p_sub_provider, p_sub_receiver, 
				'<event pending>', 10);
	end if;
	insert into "_primer_cluster2".sl_subscribe
			(sub_set, sub_provider, sub_receiver, sub_forward, sub_active)
			values (p_sub_set, p_sub_provider, p_sub_receiver,
				p_sub_forward, false);

	-- ----
	-- If the set origin is here, then enable the subscription
	-- ----
	if v_set_origin = "_primer_cluster2".getLocalNodeId('_primer_cluster2') then
		select "_primer_cluster2".createEvent('_primer_cluster2', 'ENABLE_SUBSCRIPTION', 
				p_sub_set::text, p_sub_provider::text, p_sub_receiver::text, 
				case p_sub_forward when true then 't' else 'f' end,
				case p_omit_copy when true then 't' else 'f' end
				) into v_seq_id;
		perform "_primer_cluster2".enableSubscription(p_sub_set, 
				p_sub_provider, p_sub_receiver);
	end if;
	
	-- ----
	-- Rewrite sl_listen table
	-- ----
	perform "_primer_cluster2".RebuildListenEntries();

	return p_sub_set;
end;
$$;


ALTER FUNCTION _primer_cluster2.subscribeset_int(p_sub_set integer, p_sub_provider integer, p_sub_receiver integer, p_sub_forward boolean, p_omit_copy boolean) OWNER TO postgres;

--
-- Name: FUNCTION subscribeset_int(p_sub_set integer, p_sub_provider integer, p_sub_receiver integer, p_sub_forward boolean, p_omit_copy boolean); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.subscribeset_int(p_sub_set integer, p_sub_provider integer, p_sub_receiver integer, p_sub_forward boolean, p_omit_copy boolean) IS 'subscribeSet_int (sub_set, sub_provider, sub_receiver, sub_forward, omit_copy)

Internal actions for subscribing receiver sub_receiver to subscription
set sub_set.';


--
-- Name: tablestovacuum(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.tablestovacuum() RETURNS SETOF _primer_cluster2.vactables
    LANGUAGE plpgsql
    AS $$
declare
	prec "_primer_cluster2".vactables%rowtype;
begin
	prec.nspname := '_primer_cluster2';
	prec.relname := 'sl_event';
	if "_primer_cluster2".ShouldSlonyVacuumTable(prec.nspname, prec.relname) then
		return next prec;
	end if;
	prec.nspname := '_primer_cluster2';
	prec.relname := 'sl_confirm';
	if "_primer_cluster2".ShouldSlonyVacuumTable(prec.nspname, prec.relname) then
		return next prec;
	end if;
	prec.nspname := '_primer_cluster2';
	prec.relname := 'sl_setsync';
	if "_primer_cluster2".ShouldSlonyVacuumTable(prec.nspname, prec.relname) then
		return next prec;
	end if;
	prec.nspname := '_primer_cluster2';
	prec.relname := 'sl_seqlog';
	if "_primer_cluster2".ShouldSlonyVacuumTable(prec.nspname, prec.relname) then
		return next prec;
	end if;
	prec.nspname := '_primer_cluster2';
	prec.relname := 'sl_archive_counter';
	if "_primer_cluster2".ShouldSlonyVacuumTable(prec.nspname, prec.relname) then
		return next prec;
	end if;
	prec.nspname := '_primer_cluster2';
	prec.relname := 'sl_components';
	if "_primer_cluster2".ShouldSlonyVacuumTable(prec.nspname, prec.relname) then
		return next prec;
	end if;
	prec.nspname := '_primer_cluster2';
	prec.relname := 'sl_log_script';
	if "_primer_cluster2".ShouldSlonyVacuumTable(prec.nspname, prec.relname) then
		return next prec;
	end if;
	prec.nspname := 'pg_catalog';
	prec.relname := 'pg_listener';
	if "_primer_cluster2".ShouldSlonyVacuumTable(prec.nspname, prec.relname) then
		return next prec;
	end if;
	prec.nspname := 'pg_catalog';
	prec.relname := 'pg_statistic';
	if "_primer_cluster2".ShouldSlonyVacuumTable(prec.nspname, prec.relname) then
		return next prec;
	end if;

   return;
end
$$;


ALTER FUNCTION _primer_cluster2.tablestovacuum() OWNER TO postgres;

--
-- Name: FUNCTION tablestovacuum(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.tablestovacuum() IS 'Return a list of tables that require frequent vacuuming.  The
function is used so that the list is not hardcoded into C code.';


--
-- Name: terminatenodeconnections(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.terminatenodeconnections(p_failed_node integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_row			record;
begin
	for v_row in select nl_nodeid, nl_conncnt,
			nl_backendpid from "_primer_cluster2".sl_nodelock
			where nl_nodeid = p_failed_node for update
	loop
		perform "_primer_cluster2".killBackend(v_row.nl_backendpid, 'TERM');
		delete from "_primer_cluster2".sl_nodelock
			where nl_nodeid = v_row.nl_nodeid
			and nl_conncnt = v_row.nl_conncnt;
	end loop;

	return 0;
end;
$$;


ALTER FUNCTION _primer_cluster2.terminatenodeconnections(p_failed_node integer) OWNER TO postgres;

--
-- Name: FUNCTION terminatenodeconnections(p_failed_node integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.terminatenodeconnections(p_failed_node integer) IS 'terminates all backends that have registered to be from the given node';


--
-- Name: truncateonlytable(name); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.truncateonlytable(name) RETURNS void
    LANGUAGE plpgsql
    AS $_$
begin
	execute 'truncate only '|| "_primer_cluster2".slon_quote_input($1);
end;
$_$;


ALTER FUNCTION _primer_cluster2.truncateonlytable(name) OWNER TO postgres;

--
-- Name: FUNCTION truncateonlytable(name); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.truncateonlytable(name) IS 'Calls TRUNCATE ONLY, syntax supported in version >= 8.4';


--
-- Name: uninstallnode(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.uninstallnode() RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_tab_row		record;
begin
	raise notice 'Slony-I: Please drop schema "_primer_cluster2"';
	return 0;
end;
$$;


ALTER FUNCTION _primer_cluster2.uninstallnode() OWNER TO postgres;

--
-- Name: FUNCTION uninstallnode(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.uninstallnode() IS 'Reset the whole database to standalone by removing the whole
replication system.';


--
-- Name: unlockset(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.unlockset(p_set_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_local_node_id		int4;
	v_set_row			record;
	v_tab_row			record;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Check that the set exists and that we are the origin
	-- and that it is not already locked.
	-- ----
	v_local_node_id := "_primer_cluster2".getLocalNodeId('_primer_cluster2');
	select * into v_set_row from "_primer_cluster2".sl_set
			where set_id = p_set_id
			for update;
	if not found then
		raise exception 'Slony-I: set % not found', p_set_id;
	end if;
	if v_set_row.set_origin <> v_local_node_id then
		raise exception 'Slony-I: set % does not originate on local node',
				p_set_id;
	end if;
	if v_set_row.set_locked isnull then
		raise exception 'Slony-I: set % is not locked', p_set_id;
	end if;

	-- ----
	-- Drop the lockedSet trigger from all tables in the set.
	-- ----
	for v_tab_row in select T.tab_id,
			"_primer_cluster2".slon_quote_brute(PGN.nspname) || '.' ||
			"_primer_cluster2".slon_quote_brute(PGC.relname) as tab_fqname
			from "_primer_cluster2".sl_table T,
				"pg_catalog".pg_class PGC, "pg_catalog".pg_namespace PGN
			where T.tab_set = p_set_id
				and T.tab_reloid = PGC.oid
				and PGC.relnamespace = PGN.oid
			order by tab_id
	loop
		execute 'drop trigger "_primer_cluster2_lockedset" ' || 
				'on ' || v_tab_row.tab_fqname;
	end loop;

	-- ----
	-- Clear out the set_locked field
	-- ----
	update "_primer_cluster2".sl_set
			set set_locked = NULL
			where set_id = p_set_id;

	return p_set_id;
end;
$$;


ALTER FUNCTION _primer_cluster2.unlockset(p_set_id integer) OWNER TO postgres;

--
-- Name: FUNCTION unlockset(p_set_id integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.unlockset(p_set_id integer) IS 'Remove the special trigger from all tables of a set that disables access to it.';


--
-- Name: unsubscribe_abandoned_sets(integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.unsubscribe_abandoned_sets(p_failed_node integer) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
v_row record;
v_seq_id bigint;
v_local_node int4;
begin

	select "_primer_cluster2".getLocalNodeId('_primer_cluster2') into
			   v_local_node;

	if found then
		   --abandon all subscriptions from this origin.
		for v_row in select sub_set,sub_receiver from
			"_primer_cluster2".sl_subscribe, "_primer_cluster2".sl_set
			where sub_set=set_id and set_origin=p_failed_node
			and sub_receiver=v_local_node
		loop
				raise notice 'Slony-I: failover_abandon_set() is abandoning subscription to set % on node % because it is too far ahead', v_row.sub_set,
				v_local_node;
				--If this node is a provider for the set
				--then the receiver needs to be unsubscribed.
				--
			select "_primer_cluster2".unsubscribeSet(v_row.sub_set,
												v_local_node,true)
				   into v_seq_id;
		end loop;
	end if;

	return v_seq_id;
end
$$;


ALTER FUNCTION _primer_cluster2.unsubscribe_abandoned_sets(p_failed_node integer) OWNER TO postgres;

--
-- Name: unsubscribeset(integer, integer, boolean); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.unsubscribeset(p_sub_set integer, p_sub_receiver integer, p_force boolean) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
	v_tab_row			record;
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- Check that this is called on the receiver node
	-- ----
	if p_sub_receiver != "_primer_cluster2".getLocalNodeId('_primer_cluster2') then
		raise exception 'Slony-I: unsubscribeSet() must be called on receiver';
	end if;



	-- ----
	-- Check that this does not break any chains
	-- ----
	if p_force=false and exists (select true from "_primer_cluster2".sl_subscribe
			 where sub_set = p_sub_set
				and sub_provider = p_sub_receiver)
	then
		raise exception 'Slony-I: Cannot unsubscribe set % while being provider',
				p_sub_set;
	end if;

	if exists (select true from "_primer_cluster2".sl_subscribe
			where sub_set = p_sub_set
				and sub_provider = p_sub_receiver)
	then
		--delete the receivers of this provider.
		--unsubscribeSet_int() will generate the event
		--when it runs on the receiver.
		delete from "_primer_cluster2".sl_subscribe 
			   where sub_set=p_sub_set
			   and sub_provider=p_sub_receiver;
	end if;

	-- ----
	-- Remove the replication triggers.
	-- ----
	for v_tab_row in select tab_id from "_primer_cluster2".sl_table
			where tab_set = p_sub_set
			order by tab_id
	loop
		perform "_primer_cluster2".alterTableDropTriggers(v_tab_row.tab_id);
	end loop;

	-- ----
	-- Remove the setsync status. This will also cause the
	-- worker thread to ignore the set and stop replicating
	-- right now.
	-- ----
	delete from "_primer_cluster2".sl_setsync
			where ssy_setid = p_sub_set;

	-- ----
	-- Remove all sl_table and sl_sequence entries for this set.
	-- Should we ever subscribe again, the initial data
	-- copy process will create new ones.
	-- ----
	delete from "_primer_cluster2".sl_table
			where tab_set = p_sub_set;
	delete from "_primer_cluster2".sl_sequence
			where seq_set = p_sub_set;

	-- ----
	-- Call the internal procedure to drop the subscription
	-- ----
	perform "_primer_cluster2".unsubscribeSet_int(p_sub_set, p_sub_receiver);

	-- Rewrite sl_listen table
	perform "_primer_cluster2".RebuildListenEntries();

	-- ----
	-- Create the UNSUBSCRIBE_SET event
	-- ----
	return  "_primer_cluster2".createEvent('_primer_cluster2', 'UNSUBSCRIBE_SET', 
			p_sub_set::text, p_sub_receiver::text);
end;
$$;


ALTER FUNCTION _primer_cluster2.unsubscribeset(p_sub_set integer, p_sub_receiver integer, p_force boolean) OWNER TO postgres;

--
-- Name: FUNCTION unsubscribeset(p_sub_set integer, p_sub_receiver integer, p_force boolean); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.unsubscribeset(p_sub_set integer, p_sub_receiver integer, p_force boolean) IS 'unsubscribeSet (sub_set, sub_receiver,force) 

Unsubscribe node sub_receiver from subscription set sub_set.  This is
invoked on the receiver node.  It verifies that this does not break
any chains (e.g. - where sub_receiver is a provider for another node),
then restores tables, drops Slony-specific keys, drops table entries
for the set, drops the subscription, and generates an UNSUBSCRIBE_SET
node to publish that the node is being dropped.';


--
-- Name: unsubscribeset_int(integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.unsubscribeset_int(p_sub_set integer, p_sub_receiver integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
begin
	-- ----
	-- Grab the central configuration lock
	-- ----
	lock table "_primer_cluster2".sl_config_lock;

	-- ----
	-- All the real work is done before event generation on the
	-- subscriber.
	-- ----

	--if this event unsubscribes the provider of this node
	--then this node should unsubscribe itself from the set as well.
	
	if exists (select true from 
		   "_primer_cluster2".sl_subscribe where 
		   sub_set=p_sub_set and sub_provider=p_sub_receiver
		   and sub_receiver="_primer_cluster2".getLocalNodeId('_primer_cluster2'))
	then
	   perform "_primer_cluster2".unsubscribeSet(p_sub_set,"_primer_cluster2".getLocalNodeId('_primer_cluster2'),true);
	end if;
	

	delete from "_primer_cluster2".sl_subscribe
			where sub_set = p_sub_set
				and sub_receiver = p_sub_receiver;

	-- Rewrite sl_listen table
	perform "_primer_cluster2".RebuildListenEntries();

	return p_sub_set;
end;
$$;


ALTER FUNCTION _primer_cluster2.unsubscribeset_int(p_sub_set integer, p_sub_receiver integer) OWNER TO postgres;

--
-- Name: FUNCTION unsubscribeset_int(p_sub_set integer, p_sub_receiver integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.unsubscribeset_int(p_sub_set integer, p_sub_receiver integer) IS 'unsubscribeSet_int (sub_set, sub_receiver)

All the REAL work of removing the subscriber is done before the event
is generated, so this function just has to drop the references to the
subscription in sl_subscribe.';


--
-- Name: updaterelname(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.updaterelname() RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
        v_no_id                 int4;
        v_set_origin            int4;
begin
        -- ----
        -- Grab the central configuration lock
        -- ----
        lock table "_primer_cluster2".sl_config_lock;

        update "_primer_cluster2".sl_table set 
                tab_relname = PGC.relname, tab_nspname = PGN.nspname
                from pg_catalog.pg_class PGC, pg_catalog.pg_namespace PGN 
                where "_primer_cluster2".sl_table.tab_reloid = PGC.oid
                        and PGC.relnamespace = PGN.oid and
                    (tab_relname <> PGC.relname or tab_nspname <> PGN.nspname);
        update "_primer_cluster2".sl_sequence set
                seq_relname = PGC.relname, seq_nspname = PGN.nspname
                from pg_catalog.pg_class PGC, pg_catalog.pg_namespace PGN
                where "_primer_cluster2".sl_sequence.seq_reloid = PGC.oid
                and PGC.relnamespace = PGN.oid and
 		    (seq_relname <> PGC.relname or seq_nspname <> PGN.nspname);
        return 0;
end;
$$;


ALTER FUNCTION _primer_cluster2.updaterelname() OWNER TO postgres;

--
-- Name: FUNCTION updaterelname(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.updaterelname() IS 'updateRelname()';


--
-- Name: updatereloid(integer, integer); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.updatereloid(p_set_id integer, p_only_on_node integer) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare
        v_no_id                 int4;
        v_set_origin            int4;
	prec			record;
begin
        -- ----
        -- Check that we either are the set origin or a current
        -- subscriber of the set.
        -- ----
        v_no_id := "_primer_cluster2".getLocalNodeId('_primer_cluster2');
        select set_origin into v_set_origin
                        from "_primer_cluster2".sl_set
                        where set_id = p_set_id
                        for update;
        if not found then
                raise exception 'Slony-I: set % not found', p_set_id;
        end if;
        if v_set_origin <> v_no_id
                and not exists (select 1 from "_primer_cluster2".sl_subscribe
                        where sub_set = p_set_id
                        and sub_receiver = v_no_id)
        then
                return 0;
        end if;

        -- ----
        -- If execution on only one node is requested, check that
        -- we are that node.
        -- ----
        if p_only_on_node > 0 and p_only_on_node <> v_no_id then
                return 0;
        end if;

	-- Update OIDs for tables to values pulled from non-table objects in pg_class
	-- This ensures that we won't have collisions when repairing the oids
	for prec in select tab_id from "_primer_cluster2".sl_table loop
		update "_primer_cluster2".sl_table set tab_reloid = (select oid from pg_class pc where relkind <> 'r' and not exists (select 1 from "_primer_cluster2".sl_table t2 where t2.tab_reloid = pc.oid) limit 1)
		where tab_id = prec.tab_id;
	end loop;

	for prec in select tab_id, tab_relname, tab_nspname from "_primer_cluster2".sl_table loop
	        update "_primer_cluster2".sl_table set
        	        tab_reloid = (select PGC.oid
	                from pg_catalog.pg_class PGC, pg_catalog.pg_namespace PGN
	                where "_primer_cluster2".slon_quote_brute(PGC.relname) = "_primer_cluster2".slon_quote_brute(prec.tab_relname)
	                        and PGC.relnamespace = PGN.oid
				and "_primer_cluster2".slon_quote_brute(PGN.nspname) = "_primer_cluster2".slon_quote_brute(prec.tab_nspname))
		where tab_id = prec.tab_id;
	end loop;

	for prec in select seq_id from "_primer_cluster2".sl_sequence loop
		update "_primer_cluster2".sl_sequence set seq_reloid = (select oid from pg_class pc where relkind <> 'S' and not exists (select 1 from "_primer_cluster2".sl_sequence t2 where t2.seq_reloid = pc.oid) limit 1)
		where seq_id = prec.seq_id;
	end loop;

	for prec in select seq_id, seq_relname, seq_nspname from "_primer_cluster2".sl_sequence loop
	        update "_primer_cluster2".sl_sequence set
	                seq_reloid = (select PGC.oid
	                from pg_catalog.pg_class PGC, pg_catalog.pg_namespace PGN
	                where "_primer_cluster2".slon_quote_brute(PGC.relname) = "_primer_cluster2".slon_quote_brute(prec.seq_relname)
                	and PGC.relnamespace = PGN.oid
			and "_primer_cluster2".slon_quote_brute(PGN.nspname) = "_primer_cluster2".slon_quote_brute(prec.seq_nspname))
		where seq_id = prec.seq_id;
	end loop;

	return 1;
end;
$$;


ALTER FUNCTION _primer_cluster2.updatereloid(p_set_id integer, p_only_on_node integer) OWNER TO postgres;

--
-- Name: FUNCTION updatereloid(p_set_id integer, p_only_on_node integer); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.updatereloid(p_set_id integer, p_only_on_node integer) IS 'updateReloid(set_id, only_on_node)

Updates the respective reloids in sl_table and sl_seqeunce based on
their respective FQN';


--
-- Name: upgradeschema(text); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.upgradeschema(p_old text) RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
	v_tab_row	record;
	v_query text;
	v_keepstatus text;
begin
	-- If old version is pre-2.0, then we require a special upgrade process
	if p_old like '1.%' then
		raise exception 'Upgrading to Slony-I 2.x requires running slony_upgrade_20';
	end if;

	perform "_primer_cluster2".upgradeSchemaAddTruncateTriggers();

	-- Change all Slony-I-defined columns that are "timestamp without time zone" to "timestamp *WITH* time zone"
	if exists (select 1 from information_schema.columns c
            where table_schema = '_primer_cluster2' and data_type = 'timestamp without time zone'
	    and exists (select 1 from information_schema.tables t where t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE')
		and (c.table_name, c.column_name) in (('sl_confirm', 'con_timestamp'), ('sl_event', 'ev_timestamp'), ('sl_registry', 'reg_timestamp'),('sl_archive_counter', 'ac_timestamp')))
	then

	  -- Preserve sl_status
	  select pg_get_viewdef('"_primer_cluster2".sl_status') into v_keepstatus;
	  execute 'drop view sl_status';
	  for v_tab_row in select table_schema, table_name, column_name from information_schema.columns c
            where table_schema = '_primer_cluster2' and data_type = 'timestamp without time zone'
	    and exists (select 1 from information_schema.tables t where t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE')
		and (table_name, column_name) in (('sl_confirm', 'con_timestamp'), ('sl_event', 'ev_timestamp'), ('sl_registry', 'reg_timestamp'),('sl_archive_counter', 'ac_timestamp'))
	  loop
		raise notice 'Changing Slony-I column [%.%] to timestamp WITH time zone', v_tab_row.table_name, v_tab_row.column_name;
		v_query := 'alter table ' || "_primer_cluster2".slon_quote_brute(v_tab_row.table_schema) ||
                   '.' || v_tab_row.table_name || ' alter column ' || v_tab_row.column_name ||
                   ' type timestamp with time zone;';
		execute v_query;
	  end loop;
	  -- restore sl_status
	  execute 'create view sl_status as ' || v_keepstatus;
        end if;

	if not exists (select 1 from information_schema.tables where table_schema = '_primer_cluster2' and table_name = 'sl_components') then
	   v_query := '
create table "_primer_cluster2".sl_components (
	co_actor	 text not null primary key,
	co_pid		 integer not null,
	co_node		 integer not null,
	co_connection_pid integer not null,
	co_activity	  text,
	co_starttime	  timestamptz not null,
	co_event	  bigint,
	co_eventtype 	  text
) without oids;
';
  	   execute v_query;
	end if;

	



	if not exists (select 1 from information_schema.tables t where table_schema = '_primer_cluster2' and table_name = 'sl_event_lock') then
	   v_query := 'create table "_primer_cluster2".sl_event_lock (dummy integer);';
	   execute v_query;
        end if;
	
	if not exists (select 1 from information_schema.tables t 
			where table_schema = '_primer_cluster2' 
			and table_name = 'sl_apply_stats') then
		v_query := '
			create table "_primer_cluster2".sl_apply_stats (
				as_origin			int4,
				as_num_insert		int8,
				as_num_update		int8,
				as_num_delete		int8,
				as_num_truncate		int8,
				as_num_script		int8,
				as_num_total		int8,
				as_duration			interval,
				as_apply_first		timestamptz,
				as_apply_last		timestamptz,
				as_cache_prepare	int8,
				as_cache_hit		int8,
				as_cache_evict		int8,
				as_cache_prepare_max int8
			) WITHOUT OIDS;';
		execute v_query;
	end if;
	
	--
	-- On the upgrade to 2.2, we change the layout of sl_log_N by
	-- adding columns log_tablenspname, log_tablerelname, and
	-- log_cmdupdncols as well as changing log_cmddata into
	-- log_cmdargs, which is a text array.
	--
	if not "_primer_cluster2".check_table_field_exists('_primer_cluster2', 'sl_log_1', 'log_cmdargs') then
		--
		-- Check that the cluster is completely caught up
		--
		if "_primer_cluster2".check_unconfirmed_log() then
			raise EXCEPTION 'cannot upgrade to new sl_log_N format due to existing unreplicated data';
		end if;

		--
		-- Drop tables sl_log_1 and sl_log_2
		--
		drop table "_primer_cluster2".sl_log_1;
		drop table "_primer_cluster2".sl_log_2;

		--
		-- Create the new sl_log_1
		--
		create table "_primer_cluster2".sl_log_1 (
			log_origin          int4,
			log_txid            bigint,
			log_tableid         int4,
			log_actionseq       int8,
			log_tablenspname    text,
			log_tablerelname    text,
			log_cmdtype         "char",
			log_cmdupdncols     int4,
			log_cmdargs         text[]
		) without oids;
		create index sl_log_1_idx1 on "_primer_cluster2".sl_log_1
			(log_origin, log_txid, log_actionseq);

		comment on table "_primer_cluster2".sl_log_1 is 'Stores each change to be propagated to subscriber nodes';
		comment on column "_primer_cluster2".sl_log_1.log_origin is 'Origin node from which the change came';
		comment on column "_primer_cluster2".sl_log_1.log_txid is 'Transaction ID on the origin node';
		comment on column "_primer_cluster2".sl_log_1.log_tableid is 'The table ID (from sl_table.tab_id) that this log entry is to affect';
		comment on column "_primer_cluster2".sl_log_1.log_actionseq is 'The sequence number in which actions will be applied on replicas';
		comment on column "_primer_cluster2".sl_log_1.log_tablenspname is 'The schema name of the table affected';
		comment on column "_primer_cluster2".sl_log_1.log_tablerelname is 'The table name of the table affected';
		comment on column "_primer_cluster2".sl_log_1.log_cmdtype is 'Replication action to take. U = Update, I = Insert, D = DELETE, T = TRUNCATE';
		comment on column "_primer_cluster2".sl_log_1.log_cmdupdncols is 'For cmdtype=U the number of updated columns in cmdargs';
		comment on column "_primer_cluster2".sl_log_1.log_cmdargs is 'The data needed to perform the log action on the replica';

		--
		-- Create the new sl_log_2
		--
		create table "_primer_cluster2".sl_log_2 (
			log_origin          int4,
			log_txid            bigint,
			log_tableid         int4,
			log_actionseq       int8,
			log_tablenspname    text,
			log_tablerelname    text,
			log_cmdtype         "char",
			log_cmdupdncols     int4,
			log_cmdargs         text[]
		) without oids;
		create index sl_log_2_idx1 on "_primer_cluster2".sl_log_2
			(log_origin, log_txid, log_actionseq);

		comment on table "_primer_cluster2".sl_log_2 is 'Stores each change to be propagated to subscriber nodes';
		comment on column "_primer_cluster2".sl_log_2.log_origin is 'Origin node from which the change came';
		comment on column "_primer_cluster2".sl_log_2.log_txid is 'Transaction ID on the origin node';
		comment on column "_primer_cluster2".sl_log_2.log_tableid is 'The table ID (from sl_table.tab_id) that this log entry is to affect';
		comment on column "_primer_cluster2".sl_log_2.log_actionseq is 'The sequence number in which actions will be applied on replicas';
		comment on column "_primer_cluster2".sl_log_2.log_tablenspname is 'The schema name of the table affected';
		comment on column "_primer_cluster2".sl_log_2.log_tablerelname is 'The table name of the table affected';
		comment on column "_primer_cluster2".sl_log_2.log_cmdtype is 'Replication action to take. U = Update, I = Insert, D = DELETE, T = TRUNCATE';
		comment on column "_primer_cluster2".sl_log_2.log_cmdupdncols is 'For cmdtype=U the number of updated columns in cmdargs';
		comment on column "_primer_cluster2".sl_log_2.log_cmdargs is 'The data needed to perform the log action on the replica';

		create table "_primer_cluster2".sl_log_script (
			log_origin			int4,
			log_txid			bigint,
			log_actionseq		int8,
			log_cmdtype			"char",
			log_cmdargs			text[]
			) WITHOUT OIDS;
		create index sl_log_script_idx1 on "_primer_cluster2".sl_log_script
		(log_origin, log_txid, log_actionseq);

		comment on table "_primer_cluster2".sl_log_script is 'Captures SQL script queries to be propagated to subscriber nodes';
		comment on column "_primer_cluster2".sl_log_script.log_origin is 'Origin name from which the change came';
		comment on column "_primer_cluster2".sl_log_script.log_txid is 'Transaction ID on the origin node';
		comment on column "_primer_cluster2".sl_log_script.log_actionseq is 'The sequence number in which actions will be applied on replicas';
		comment on column "_primer_cluster2".sl_log_2.log_cmdtype is 'Replication action to take. S = Script statement, s = Script complete';
		comment on column "_primer_cluster2".sl_log_script.log_cmdargs is 'The DDL statement, optionally followed by selected nodes to execute it on.';

		--
		-- Put the log apply triggers back onto sl_log_1/2
		--
		create trigger apply_trigger
			before INSERT on "_primer_cluster2".sl_log_1
			for each row execute procedure "_primer_cluster2".logApply('_primer_cluster2');
		alter table "_primer_cluster2".sl_log_1
			enable replica trigger apply_trigger;
		create trigger apply_trigger
			before INSERT on "_primer_cluster2".sl_log_2
			for each row execute procedure "_primer_cluster2".logApply('_primer_cluster2');
		alter table "_primer_cluster2".sl_log_2
			enable replica trigger apply_trigger;
	end if;
	if not exists (select 1 from information_schema.routines where routine_schema = '_primer_cluster2' and routine_name = 'string_agg') then
	       CREATE AGGREGATE "_primer_cluster2".string_agg(text) (
	   	      SFUNC="_primer_cluster2".agg_text_sum,
		      STYPE=text,
		      INITCOND=''
		      );
	end if;
	if not exists (select 1 from information_schema.views where table_schema='_primer_cluster2' and table_name='sl_failover_targets') then
	   create view "_primer_cluster2".sl_failover_targets as
	   	  select  set_id,
		  set_origin as set_origin,
		  sub1.sub_receiver as backup_id

		  FROM
		  "_primer_cluster2".sl_subscribe sub1
		  ,"_primer_cluster2".sl_set set1
		  where
 		  sub1.sub_set=set_id
		  and sub1.sub_forward=true
		  --exclude candidates where the set_origin
		  --has a path a node but the failover
		  --candidate has no path to that node
		  and sub1.sub_receiver not in
	    	  (select p1.pa_client from
	    	  "_primer_cluster2".sl_path p1 
	    	  left outer join "_primer_cluster2".sl_path p2 on
	    	  (p2.pa_client=p1.pa_client 
	    	  and p2.pa_server=sub1.sub_receiver)
	    	  where p2.pa_client is null
	    	  and p1.pa_server=set_origin
	    	  and p1.pa_client<>sub1.sub_receiver
	    	  )
		  and sub1.sub_provider=set_origin
		  --exclude any subscribers that are not
		  --direct subscribers of all sets on the
		  --origin
		  and sub1.sub_receiver not in
		  (select direct_recv.sub_receiver
		  from
			
			(--all direct receivers of the first set
			select subs2.sub_receiver
			from "_primer_cluster2".sl_subscribe subs2
			where subs2.sub_provider=set1.set_origin
		      	and subs2.sub_set=set1.set_id) as
		      	direct_recv
			inner join
			(--all other sets from the origin
			select set_id from "_primer_cluster2".sl_set set2
			where set2.set_origin=set1.set_origin
			and set2.set_id<>sub1.sub_set)
			as othersets on(true)
			left outer join "_primer_cluster2".sl_subscribe subs3
			on(subs3.sub_set=othersets.set_id
		   	and subs3.sub_forward=true
		   	and subs3.sub_provider=set1.set_origin
		   	and direct_recv.sub_receiver=subs3.sub_receiver)
	    		where subs3.sub_receiver is null
	    	);
	end if;

	if not "_primer_cluster2".check_table_field_exists('_primer_cluster2', 'sl_node', 'no_failed') then
	   alter table "_primer_cluster2".sl_node add column no_failed bool;
	   update "_primer_cluster2".sl_node set no_failed=false;
	end if;
	return p_old;
end;
$$;


ALTER FUNCTION _primer_cluster2.upgradeschema(p_old text) OWNER TO postgres;

--
-- Name: FUNCTION upgradeschema(p_old text); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.upgradeschema(p_old text) IS 'Called during "update functions" by slonik to perform schema changes';


--
-- Name: upgradeschemaaddtruncatetriggers(); Type: FUNCTION; Schema: _primer_cluster2; Owner: postgres
--

CREATE FUNCTION _primer_cluster2.upgradeschemaaddtruncatetriggers() RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin

		--- Add truncate triggers
		begin		
		perform "_primer_cluster2".alterTableAddTruncateTrigger("_primer_cluster2".slon_quote_brute(tab_nspname) || '.' || "_primer_cluster2".slon_quote_brute(tab_relname), tab_id)
				from "_primer_cluster2".sl_table
                where 2 <> (select count(*) from pg_catalog.pg_trigger,
					  pg_catalog.pg_class, pg_catalog.pg_namespace where 
					  pg_trigger.tgrelid=pg_class.oid
					  AND pg_class.relnamespace=pg_namespace.oid
					  AND
					  pg_namespace.nspname = tab_nspname and tgname in ('_primer_cluster2_truncatedeny', '_primer_cluster2_truncatetrigger') and
                      pg_class.relname = tab_relname
					  );

		exception when unique_violation then
				  raise warning 'upgradeSchemaAddTruncateTriggers() - uniqueness violation';
				  raise warning 'likely due to truncate triggers existing partially';
				  raise exception 'upgradeSchemaAddTruncateTriggers() - failure - [%][%]', SQLSTATE, SQLERRM;
		end;

		-- Activate truncate triggers for replica
		perform "_primer_cluster2".alterTableConfigureTruncateTrigger("_primer_cluster2".slon_quote_brute(tab_nspname) || '.' || "_primer_cluster2".slon_quote_brute(tab_relname)
		,'disable','enable') 
		        from "_primer_cluster2".sl_table
                where tab_set not in (select set_id from "_primer_cluster2".sl_set where set_origin = "_primer_cluster2".getLocalNodeId('_primer_cluster2'))
                      and exists (select 1 from  pg_catalog.pg_trigger
                                           where pg_trigger.tgname like '_primer_cluster2_truncatetrigger' and pg_trigger.tgenabled = 'O'
                                                 and pg_trigger.tgrelid=tab_reloid ) 
                      and  exists (select 1 from  pg_catalog.pg_trigger
                                            where pg_trigger.tgname like '_primer_cluster2_truncatedeny' and pg_trigger.tgenabled = 'D' 
                                                  and pg_trigger.tgrelid=tab_reloid);

		-- Activate truncate triggers for origin
		perform "_primer_cluster2".alterTableConfigureTruncateTrigger("_primer_cluster2".slon_quote_brute(tab_nspname) || '.' || "_primer_cluster2".slon_quote_brute(tab_relname)
		,'enable','disable') 
		        from "_primer_cluster2".sl_table
                where tab_set in (select set_id from "_primer_cluster2".sl_set where set_origin = "_primer_cluster2".getLocalNodeId('_primer_cluster2'))
                      and exists (select 1 from  pg_catalog.pg_trigger
                                           where pg_trigger.tgname like '_primer_cluster2_truncatetrigger' and pg_trigger.tgenabled = 'D'
                                                 and pg_trigger.tgrelid=tab_reloid )                                                    
                      and  exists (select 1 from  pg_catalog.pg_trigger
                                            where pg_trigger.tgname like '_primer_cluster2_truncatedeny' and pg_trigger.tgenabled = 'O'
                                                  and pg_trigger.tgrelid=tab_reloid);

		return 1;
end
$$;


ALTER FUNCTION _primer_cluster2.upgradeschemaaddtruncatetriggers() OWNER TO postgres;

--
-- Name: FUNCTION upgradeschemaaddtruncatetriggers(); Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON FUNCTION _primer_cluster2.upgradeschemaaddtruncatetriggers() IS 'Add ON TRUNCATE triggers to replicated tables.';


--
-- Name: alta_agentes(character varying, character varying, character varying, character varying, bigint); Type: FUNCTION; Schema: comercial; Owner: postgres
--

CREATE FUNCTION comercial.alta_agentes(apellidop character varying, apellidom character varying, nombre character varying, rfc character varying, zona bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
   IF (length(rfc)>13) THEN
  RAISE EXCEPTION 'RFC debe ser de 13 caracteres--> %', rfc;       
   END IF;

   IF (length(rfc)<13) THEN
  RAISE EXCEPTION 'RFC debe ser de 13 caracteres--> %', rfc;       
   END IF;
  INSERT INTO comercial.agente(apellido_paterno, apellido_materno, nombre, rfc, zona_id) VALUES (apellidop,apellidom,nombre,rfc,zona);
END;
$$;


ALTER FUNCTION comercial.alta_agentes(apellidop character varying, apellidom character varying, nombre character varying, rfc character varying, zona bigint) OWNER TO postgres;

--
-- Name: baja_agentes(bigint); Type: FUNCTION; Schema: comercial; Owner: postgres
--

CREATE FUNCTION comercial.baja_agentes(_id bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
IF not exists (Select id from Comercial.Agente where agente.id=_id) THEN
  RAISE EXCEPTION 'Agente ID no existe --> %', _id USING HINT = 'Por favor checa el ID del Agente';
END IF;
IF(SELECT count(*) FROM comercial.agente,CXC.clientes where agente.id=_id and agente.id=clientes.agente_id)>0 THEN
RAISE EXCEPTION 'El agente cuenta con clientes,asignelos a otro agente por favor';
END IF;
DELETE FROM comercial.agente WHERE agente.id = _id;
END;
$$;


ALTER FUNCTION comercial.baja_agentes(_id bigint) OWNER TO postgres;

--
-- Name: modif_agentes(bigint, character varying, character varying, character varying, character varying, bigint); Type: FUNCTION; Schema: comercial; Owner: postgres
--

CREATE FUNCTION comercial.modif_agentes(_id bigint, apellidop character varying, apellidom character varying, _nombre character varying, _rfc character varying, zona bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
IF (length(_rfc)>13) THEN
  RAISE EXCEPTION 'RFC debe ser de 13 caracteres--> %', _rfc;       
   END IF;
   IF (length(_rfc)<13) THEN
  RAISE EXCEPTION 'RFC debe ser de 13 caracteres--> %', _rfc;       
   END IF;
UPDATE Comercial.Agente SET (apellido_paterno, apellido_materno, nombre, rfc, zona_id) = (apellidop,apellidom,_nombre,_rfc,zona)
  WHERE id=_id;
END;
$$;


ALTER FUNCTION comercial.modif_agentes(_id bigint, apellidop character varying, apellidom character varying, _nombre character varying, _rfc character varying, zona bigint) OWNER TO postgres;

--
-- Name: alta_clientes(character varying, character varying, character varying, character varying, bigint); Type: FUNCTION; Schema: cxc; Owner: postgres
--

CREATE FUNCTION cxc.alta_clientes(nombre character varying, apellidop character varying, apellidom character varying, rfc character varying, agentes bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF not exists (Select id from Comercial.Agente where id=agentes) THEN
  RAISE EXCEPTION 'Agente ID no existe --> %', agentes USING HINT = 'Por favor checa el ID del Agente';        
  END IF;
  INSERT INTO CXC.Clientes(nombre, apellido_paterno, apellido_materno,  rfc, agente_id) VALUES (nombre,apellidop,apellidom,rfc,agentes);       
END
$$;


ALTER FUNCTION cxc.alta_clientes(nombre character varying, apellidop character varying, apellidom character varying, rfc character varying, agentes bigint) OWNER TO postgres;

--
-- Name: baja_clientes(bigint); Type: FUNCTION; Schema: cxc; Owner: postgres
--

CREATE FUNCTION cxc.baja_clientes(_id bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
IF not exists (Select id from CXC.Clientes where Clientes.id=_id) THEN
  RAISE EXCEPTION 'Cliente ID no existe --> %', _id USING HINT = 'Por favor checa el ID del Cliente';
END IF;
DELETE FROM CXC.Clientes WHERE Clientes.id = _id;
END;
$$;


ALTER FUNCTION cxc.baja_clientes(_id bigint) OWNER TO postgres;

--
-- Name: clientes_id_insert(); Type: FUNCTION; Schema: cxc; Owner: postgres
--

CREATE FUNCTION cxc.clientes_id_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
IF (NEW.id%2)=0 THEN
INSERT INTO CXC.Clientes_par VALUES (NEW.*);
ELSE
INSERT INTO CXC.Clientes_impar VALUES (NEW.*);
END IF;
RETURN NULL;
END;
$$;


ALTER FUNCTION cxc.clientes_id_insert() OWNER TO postgres;

--
-- Name: modif_clientes(bigint, character varying, character varying, character varying, character varying, bigint); Type: FUNCTION; Schema: cxc; Owner: postgres
--

CREATE FUNCTION cxc.modif_clientes(_id bigint, _nombre character varying, apellidop character varying, apellidom character varying, _rfc character varying, agentes bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
IF not exists (Select id from Comercial.Agente where id=agentes) THEN
  RAISE EXCEPTION 'Agente ID no existe --> %', agentes USING HINT = 'Por favor checa el ID del Agente';        
  END IF;
IF (length(_rfc)>13) THEN
  RAISE EXCEPTION 'RFC debe ser de 13 caracteres--> %', _rfc;       
   END IF;
   IF (length(_rfc)<13) THEN
  RAISE EXCEPTION 'RFC debe ser de 13 caracteres--> %', _rfc;       
   END IF;
UPDATE CXC.Clientes SET (nombre,apellido_paterno, apellido_materno,rfc, agente_id) = (_nombre,apellidop,apellidom,_rfc,agentes)
  WHERE id=_id;
END;
$$;


ALTER FUNCTION cxc.modif_clientes(_id bigint, _nombre character varying, apellidop character varying, apellidom character varying, _rfc character varying, agentes bigint) OWNER TO postgres;

--
-- Name: string_agg(text); Type: AGGREGATE; Schema: _primer_cluster2; Owner: postgres
--

CREATE AGGREGATE _primer_cluster2.string_agg(text) (
    SFUNC = _primer_cluster2.agg_text_sum,
    STYPE = text,
    INITCOND = ''
);


ALTER AGGREGATE _primer_cluster2.string_agg(text) OWNER TO postgres;

--
-- Name: sl_action_seq; Type: SEQUENCE; Schema: _primer_cluster2; Owner: postgres
--

CREATE SEQUENCE _primer_cluster2.sl_action_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE _primer_cluster2.sl_action_seq OWNER TO postgres;

--
-- Name: SEQUENCE sl_action_seq; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON SEQUENCE _primer_cluster2.sl_action_seq IS 'The sequence to number statements in the transaction logs, so that the replication engines can figure out the "agreeable" order of statements.';


SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: sl_apply_stats; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_apply_stats (
    as_origin integer,
    as_num_insert bigint,
    as_num_update bigint,
    as_num_delete bigint,
    as_num_truncate bigint,
    as_num_script bigint,
    as_num_total bigint,
    as_duration interval,
    as_apply_first timestamp with time zone,
    as_apply_last timestamp with time zone,
    as_cache_prepare bigint,
    as_cache_hit bigint,
    as_cache_evict bigint,
    as_cache_prepare_max bigint
);


ALTER TABLE _primer_cluster2.sl_apply_stats OWNER TO postgres;

--
-- Name: TABLE sl_apply_stats; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_apply_stats IS 'Local SYNC apply statistics (running totals)';


--
-- Name: COLUMN sl_apply_stats.as_origin; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_apply_stats.as_origin IS 'Origin of the SYNCs';


--
-- Name: COLUMN sl_apply_stats.as_num_insert; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_apply_stats.as_num_insert IS 'Number of INSERT operations performed';


--
-- Name: COLUMN sl_apply_stats.as_num_update; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_apply_stats.as_num_update IS 'Number of UPDATE operations performed';


--
-- Name: COLUMN sl_apply_stats.as_num_delete; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_apply_stats.as_num_delete IS 'Number of DELETE operations performed';


--
-- Name: COLUMN sl_apply_stats.as_num_truncate; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_apply_stats.as_num_truncate IS 'Number of TRUNCATE operations performed';


--
-- Name: COLUMN sl_apply_stats.as_num_script; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_apply_stats.as_num_script IS 'Number of DDL operations performed';


--
-- Name: COLUMN sl_apply_stats.as_num_total; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_apply_stats.as_num_total IS 'Total number of operations';


--
-- Name: COLUMN sl_apply_stats.as_duration; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_apply_stats.as_duration IS 'Processing time';


--
-- Name: COLUMN sl_apply_stats.as_apply_first; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_apply_stats.as_apply_first IS 'Timestamp of first recorded SYNC';


--
-- Name: COLUMN sl_apply_stats.as_apply_last; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_apply_stats.as_apply_last IS 'Timestamp of most recent recorded SYNC';


--
-- Name: COLUMN sl_apply_stats.as_cache_evict; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_apply_stats.as_cache_evict IS 'Number of apply query cache evict operations';


--
-- Name: COLUMN sl_apply_stats.as_cache_prepare_max; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_apply_stats.as_cache_prepare_max IS 'Maximum number of apply queries prepared in one SYNC group';


--
-- Name: sl_archive_counter; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_archive_counter (
    ac_num bigint,
    ac_timestamp timestamp with time zone
);


ALTER TABLE _primer_cluster2.sl_archive_counter OWNER TO postgres;

--
-- Name: TABLE sl_archive_counter; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_archive_counter IS 'Table used to generate the log shipping archive number.
';


--
-- Name: COLUMN sl_archive_counter.ac_num; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_archive_counter.ac_num IS 'Counter of SYNC ID used in log shipping as the archive number';


--
-- Name: COLUMN sl_archive_counter.ac_timestamp; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_archive_counter.ac_timestamp IS 'Time at which the archive log was generated on the subscriber';


--
-- Name: sl_components; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_components (
    co_actor text NOT NULL,
    co_pid integer NOT NULL,
    co_node integer NOT NULL,
    co_connection_pid integer NOT NULL,
    co_activity text,
    co_starttime timestamp with time zone NOT NULL,
    co_event bigint,
    co_eventtype text
);


ALTER TABLE _primer_cluster2.sl_components OWNER TO postgres;

--
-- Name: TABLE sl_components; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_components IS 'Table used to monitor what various slon/slonik components are doing';


--
-- Name: COLUMN sl_components.co_actor; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_components.co_actor IS 'which component am I?';


--
-- Name: COLUMN sl_components.co_pid; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_components.co_pid IS 'my process/thread PID on node where slon runs';


--
-- Name: COLUMN sl_components.co_node; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_components.co_node IS 'which node am I servicing?';


--
-- Name: COLUMN sl_components.co_connection_pid; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_components.co_connection_pid IS 'PID of database connection being used on database server';


--
-- Name: COLUMN sl_components.co_activity; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_components.co_activity IS 'activity that I am up to';


--
-- Name: COLUMN sl_components.co_starttime; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_components.co_starttime IS 'when did my activity begin?  (timestamp reported as per slon process on server running slon)';


--
-- Name: COLUMN sl_components.co_event; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_components.co_event IS 'which event have I started processing?';


--
-- Name: COLUMN sl_components.co_eventtype; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_components.co_eventtype IS 'what kind of event am I processing?  (commonly n/a for event loop main threads)';


--
-- Name: sl_config_lock; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_config_lock (
    dummy integer
);


ALTER TABLE _primer_cluster2.sl_config_lock OWNER TO postgres;

--
-- Name: TABLE sl_config_lock; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_config_lock IS 'This table exists solely to prevent overlapping execution of configuration change procedures and the resulting possible deadlocks.
';


--
-- Name: COLUMN sl_config_lock.dummy; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_config_lock.dummy IS 'No data ever goes in this table so the contents never matter.  Indeed, this column does not really need to exist.';


--
-- Name: sl_confirm; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_confirm (
    con_origin integer,
    con_received integer,
    con_seqno bigint,
    con_timestamp timestamp with time zone DEFAULT (timeofday())::timestamp with time zone
);


ALTER TABLE _primer_cluster2.sl_confirm OWNER TO postgres;

--
-- Name: TABLE sl_confirm; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_confirm IS 'Holds confirmation of replication events.  After a period of time, Slony removes old confirmed events from both this table and the sl_event table.';


--
-- Name: COLUMN sl_confirm.con_origin; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_confirm.con_origin IS 'The ID # (from sl_node.no_id) of the source node for this event';


--
-- Name: COLUMN sl_confirm.con_seqno; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_confirm.con_seqno IS 'The ID # for the event';


--
-- Name: COLUMN sl_confirm.con_timestamp; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_confirm.con_timestamp IS 'When this event was confirmed';


--
-- Name: sl_event; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_event (
    ev_origin integer NOT NULL,
    ev_seqno bigint NOT NULL,
    ev_timestamp timestamp with time zone,
    ev_snapshot txid_snapshot,
    ev_type text,
    ev_data1 text,
    ev_data2 text,
    ev_data3 text,
    ev_data4 text,
    ev_data5 text,
    ev_data6 text,
    ev_data7 text,
    ev_data8 text
);


ALTER TABLE _primer_cluster2.sl_event OWNER TO postgres;

--
-- Name: TABLE sl_event; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_event IS 'Holds information about replication events.  After a period of time, Slony removes old confirmed events from both this table and the sl_confirm table.';


--
-- Name: COLUMN sl_event.ev_origin; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_event.ev_origin IS 'The ID # (from sl_node.no_id) of the source node for this event';


--
-- Name: COLUMN sl_event.ev_seqno; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_event.ev_seqno IS 'The ID # for the event';


--
-- Name: COLUMN sl_event.ev_timestamp; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_event.ev_timestamp IS 'When this event record was created';


--
-- Name: COLUMN sl_event.ev_snapshot; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_event.ev_snapshot IS 'TXID snapshot on provider node for this event';


--
-- Name: COLUMN sl_event.ev_type; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_event.ev_type IS 'The type of event this record is for.  
				SYNC				= Synchronise
				STORE_NODE			=
				ENABLE_NODE			=
				DROP_NODE			=
				STORE_PATH			=
				DROP_PATH			=
				STORE_LISTEN		=
				DROP_LISTEN			=
				STORE_SET			=
				DROP_SET			=
				MERGE_SET			=
				SET_ADD_TABLE		=
				SET_ADD_SEQUENCE	=
				STORE_TRIGGER		=
				DROP_TRIGGER		=
				MOVE_SET			=
				ACCEPT_SET			=
				SET_DROP_TABLE			=
				SET_DROP_SEQUENCE		=
				SET_MOVE_TABLE			=
				SET_MOVE_SEQUENCE		=
				FAILOVER_SET		=
				SUBSCRIBE_SET		=
				ENABLE_SUBSCRIPTION	=
				UNSUBSCRIBE_SET		=
				DDL_SCRIPT			=
				ADJUST_SEQ			=
				RESET_CONFIG		=
';


--
-- Name: COLUMN sl_event.ev_data1; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_event.ev_data1 IS 'Data field containing an argument needed to process the event';


--
-- Name: COLUMN sl_event.ev_data2; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_event.ev_data2 IS 'Data field containing an argument needed to process the event';


--
-- Name: COLUMN sl_event.ev_data3; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_event.ev_data3 IS 'Data field containing an argument needed to process the event';


--
-- Name: COLUMN sl_event.ev_data4; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_event.ev_data4 IS 'Data field containing an argument needed to process the event';


--
-- Name: COLUMN sl_event.ev_data5; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_event.ev_data5 IS 'Data field containing an argument needed to process the event';


--
-- Name: COLUMN sl_event.ev_data6; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_event.ev_data6 IS 'Data field containing an argument needed to process the event';


--
-- Name: COLUMN sl_event.ev_data7; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_event.ev_data7 IS 'Data field containing an argument needed to process the event';


--
-- Name: COLUMN sl_event.ev_data8; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_event.ev_data8 IS 'Data field containing an argument needed to process the event';


--
-- Name: sl_event_lock; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_event_lock (
    dummy integer
);


ALTER TABLE _primer_cluster2.sl_event_lock OWNER TO postgres;

--
-- Name: TABLE sl_event_lock; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_event_lock IS 'This table exists solely to prevent multiple connections from concurrently creating new events and perhaps getting them out of order.';


--
-- Name: COLUMN sl_event_lock.dummy; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_event_lock.dummy IS 'No data ever goes in this table so the contents never matter.  Indeed, this column does not really need to exist.';


--
-- Name: sl_event_seq; Type: SEQUENCE; Schema: _primer_cluster2; Owner: postgres
--

CREATE SEQUENCE _primer_cluster2.sl_event_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE _primer_cluster2.sl_event_seq OWNER TO postgres;

--
-- Name: SEQUENCE sl_event_seq; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON SEQUENCE _primer_cluster2.sl_event_seq IS 'The sequence for numbering events originating from this node.';


--
-- Name: sl_path; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_path (
    pa_server integer NOT NULL,
    pa_client integer NOT NULL,
    pa_conninfo text NOT NULL,
    pa_connretry integer
);


ALTER TABLE _primer_cluster2.sl_path OWNER TO postgres;

--
-- Name: TABLE sl_path; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_path IS 'Holds connection information for the paths between nodes, and the synchronisation delay';


--
-- Name: COLUMN sl_path.pa_server; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_path.pa_server IS 'The Node ID # (from sl_node.no_id) of the data source';


--
-- Name: COLUMN sl_path.pa_client; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_path.pa_client IS 'The Node ID # (from sl_node.no_id) of the data target';


--
-- Name: COLUMN sl_path.pa_conninfo; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_path.pa_conninfo IS 'The PostgreSQL connection string used to connect to the source node.';


--
-- Name: COLUMN sl_path.pa_connretry; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_path.pa_connretry IS 'The synchronisation delay, in seconds';


--
-- Name: sl_set; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_set (
    set_id integer NOT NULL,
    set_origin integer,
    set_locked bigint,
    set_comment text
);


ALTER TABLE _primer_cluster2.sl_set OWNER TO postgres;

--
-- Name: TABLE sl_set; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_set IS 'Holds definitions of replication sets.';


--
-- Name: COLUMN sl_set.set_id; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_set.set_id IS 'A unique ID number for the set.';


--
-- Name: COLUMN sl_set.set_origin; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_set.set_origin IS 'The ID number of the source node for the replication set.';


--
-- Name: COLUMN sl_set.set_locked; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_set.set_locked IS 'Transaction ID where the set was locked.';


--
-- Name: COLUMN sl_set.set_comment; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_set.set_comment IS 'A human-oriented description of the set.';


--
-- Name: sl_subscribe; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_subscribe (
    sub_set integer NOT NULL,
    sub_provider integer,
    sub_receiver integer NOT NULL,
    sub_forward boolean,
    sub_active boolean
);


ALTER TABLE _primer_cluster2.sl_subscribe OWNER TO postgres;

--
-- Name: TABLE sl_subscribe; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_subscribe IS 'Holds a list of subscriptions on sets';


--
-- Name: COLUMN sl_subscribe.sub_set; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_subscribe.sub_set IS 'ID # (from sl_set) of the set being subscribed to';


--
-- Name: COLUMN sl_subscribe.sub_provider; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_subscribe.sub_provider IS 'ID# (from sl_node) of the node providing data';


--
-- Name: COLUMN sl_subscribe.sub_receiver; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_subscribe.sub_receiver IS 'ID# (from sl_node) of the node receiving data from the provider';


--
-- Name: COLUMN sl_subscribe.sub_forward; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_subscribe.sub_forward IS 'Does this provider keep data in sl_log_1/sl_log_2 to allow it to be a provider for other nodes?';


--
-- Name: COLUMN sl_subscribe.sub_active; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_subscribe.sub_active IS 'Has this subscription been activated?  This is not set on the subscriber until AFTER the subscriber has received COPY data from the provider';


--
-- Name: sl_failover_targets; Type: VIEW; Schema: _primer_cluster2; Owner: postgres
--

CREATE VIEW _primer_cluster2.sl_failover_targets AS
 SELECT set1.set_id,
    set1.set_origin,
    sub1.sub_receiver AS backup_id
   FROM _primer_cluster2.sl_subscribe sub1,
    _primer_cluster2.sl_set set1
  WHERE ((sub1.sub_set = set1.set_id) AND (sub1.sub_forward = true) AND (NOT (sub1.sub_receiver IN ( SELECT p1.pa_client
           FROM (_primer_cluster2.sl_path p1
             LEFT JOIN _primer_cluster2.sl_path p2 ON (((p2.pa_client = p1.pa_client) AND (p2.pa_server = sub1.sub_receiver))))
          WHERE ((p2.pa_client IS NULL) AND (p1.pa_server = set1.set_origin) AND (p1.pa_client <> sub1.sub_receiver))))) AND (sub1.sub_provider = set1.set_origin) AND (NOT (sub1.sub_receiver IN ( SELECT direct_recv.sub_receiver
           FROM ((( SELECT subs2.sub_receiver
                   FROM _primer_cluster2.sl_subscribe subs2
                  WHERE ((subs2.sub_provider = set1.set_origin) AND (subs2.sub_set = set1.set_id))) direct_recv
             JOIN ( SELECT set2.set_id
                   FROM _primer_cluster2.sl_set set2
                  WHERE ((set2.set_origin = set1.set_origin) AND (set2.set_id <> sub1.sub_set))) othersets ON (true))
             LEFT JOIN _primer_cluster2.sl_subscribe subs3 ON (((subs3.sub_set = othersets.set_id) AND (subs3.sub_forward = true) AND (subs3.sub_provider = set1.set_origin) AND (direct_recv.sub_receiver = subs3.sub_receiver))))
          WHERE (subs3.sub_receiver IS NULL)))));


ALTER TABLE _primer_cluster2.sl_failover_targets OWNER TO postgres;

--
-- Name: sl_listen; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_listen (
    li_origin integer NOT NULL,
    li_provider integer NOT NULL,
    li_receiver integer NOT NULL
);


ALTER TABLE _primer_cluster2.sl_listen OWNER TO postgres;

--
-- Name: TABLE sl_listen; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_listen IS 'Indicates how nodes listen to events from other nodes in the Slony-I network.';


--
-- Name: COLUMN sl_listen.li_origin; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_listen.li_origin IS 'The ID # (from sl_node.no_id) of the node this listener is operating on';


--
-- Name: COLUMN sl_listen.li_provider; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_listen.li_provider IS 'The ID # (from sl_node.no_id) of the source node for this listening event';


--
-- Name: COLUMN sl_listen.li_receiver; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_listen.li_receiver IS 'The ID # (from sl_node.no_id) of the target node for this listening event';


--
-- Name: sl_local_node_id; Type: SEQUENCE; Schema: _primer_cluster2; Owner: postgres
--

CREATE SEQUENCE _primer_cluster2.sl_local_node_id
    START WITH -1
    INCREMENT BY 1
    MINVALUE -1
    NO MAXVALUE
    CACHE 1;


ALTER TABLE _primer_cluster2.sl_local_node_id OWNER TO postgres;

--
-- Name: SEQUENCE sl_local_node_id; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON SEQUENCE _primer_cluster2.sl_local_node_id IS 'The local node ID is initialized to -1, meaning that this node is not initialized yet.';


--
-- Name: sl_log_1; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_log_1 (
    log_origin integer,
    log_txid bigint,
    log_tableid integer,
    log_actionseq bigint,
    log_tablenspname text,
    log_tablerelname text,
    log_cmdtype "char",
    log_cmdupdncols integer,
    log_cmdargs text[]
);


ALTER TABLE _primer_cluster2.sl_log_1 OWNER TO postgres;

--
-- Name: TABLE sl_log_1; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_log_1 IS 'Stores each change to be propagated to subscriber nodes';


--
-- Name: COLUMN sl_log_1.log_origin; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_1.log_origin IS 'Origin node from which the change came';


--
-- Name: COLUMN sl_log_1.log_txid; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_1.log_txid IS 'Transaction ID on the origin node';


--
-- Name: COLUMN sl_log_1.log_tableid; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_1.log_tableid IS 'The table ID (from sl_table.tab_id) that this log entry is to affect';


--
-- Name: COLUMN sl_log_1.log_actionseq; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_1.log_actionseq IS 'The sequence number in which actions will be applied on replicas';


--
-- Name: COLUMN sl_log_1.log_tablenspname; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_1.log_tablenspname IS 'The schema name of the table affected';


--
-- Name: COLUMN sl_log_1.log_tablerelname; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_1.log_tablerelname IS 'The table name of the table affected';


--
-- Name: COLUMN sl_log_1.log_cmdtype; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_1.log_cmdtype IS 'Replication action to take. U = Update, I = Insert, D = DELETE, T = TRUNCATE';


--
-- Name: COLUMN sl_log_1.log_cmdupdncols; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_1.log_cmdupdncols IS 'For cmdtype=U the number of updated columns in cmdargs';


--
-- Name: COLUMN sl_log_1.log_cmdargs; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_1.log_cmdargs IS 'The data needed to perform the log action on the replica';


--
-- Name: sl_log_2; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_log_2 (
    log_origin integer,
    log_txid bigint,
    log_tableid integer,
    log_actionseq bigint,
    log_tablenspname text,
    log_tablerelname text,
    log_cmdtype "char",
    log_cmdupdncols integer,
    log_cmdargs text[]
);


ALTER TABLE _primer_cluster2.sl_log_2 OWNER TO postgres;

--
-- Name: TABLE sl_log_2; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_log_2 IS 'Stores each change to be propagated to subscriber nodes';


--
-- Name: COLUMN sl_log_2.log_origin; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_2.log_origin IS 'Origin node from which the change came';


--
-- Name: COLUMN sl_log_2.log_txid; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_2.log_txid IS 'Transaction ID on the origin node';


--
-- Name: COLUMN sl_log_2.log_tableid; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_2.log_tableid IS 'The table ID (from sl_table.tab_id) that this log entry is to affect';


--
-- Name: COLUMN sl_log_2.log_actionseq; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_2.log_actionseq IS 'The sequence number in which actions will be applied on replicas';


--
-- Name: COLUMN sl_log_2.log_tablenspname; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_2.log_tablenspname IS 'The schema name of the table affected';


--
-- Name: COLUMN sl_log_2.log_tablerelname; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_2.log_tablerelname IS 'The table name of the table affected';


--
-- Name: COLUMN sl_log_2.log_cmdtype; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_2.log_cmdtype IS 'Replication action to take. S = Script statement, s = Script complete';


--
-- Name: COLUMN sl_log_2.log_cmdupdncols; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_2.log_cmdupdncols IS 'For cmdtype=U the number of updated columns in cmdargs';


--
-- Name: COLUMN sl_log_2.log_cmdargs; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_2.log_cmdargs IS 'The data needed to perform the log action on the replica';


--
-- Name: sl_log_script; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_log_script (
    log_origin integer,
    log_txid bigint,
    log_actionseq bigint,
    log_cmdtype "char",
    log_cmdargs text[]
);


ALTER TABLE _primer_cluster2.sl_log_script OWNER TO postgres;

--
-- Name: TABLE sl_log_script; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_log_script IS 'Captures SQL script queries to be propagated to subscriber nodes';


--
-- Name: COLUMN sl_log_script.log_origin; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_script.log_origin IS 'Origin name from which the change came';


--
-- Name: COLUMN sl_log_script.log_txid; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_script.log_txid IS 'Transaction ID on the origin node';


--
-- Name: COLUMN sl_log_script.log_actionseq; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_script.log_actionseq IS 'The sequence number in which actions will be applied on replicas';


--
-- Name: COLUMN sl_log_script.log_cmdargs; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_log_script.log_cmdargs IS 'The DDL statement, optionally followed by selected nodes to execute it on.';


--
-- Name: sl_log_status; Type: SEQUENCE; Schema: _primer_cluster2; Owner: postgres
--

CREATE SEQUENCE _primer_cluster2.sl_log_status
    START WITH 0
    INCREMENT BY 1
    MINVALUE 0
    MAXVALUE 3
    CACHE 1;


ALTER TABLE _primer_cluster2.sl_log_status OWNER TO postgres;

--
-- Name: SEQUENCE sl_log_status; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON SEQUENCE _primer_cluster2.sl_log_status IS '
Bit 0x01 determines the currently active log table
Bit 0x02 tells if the engine needs to read both logs
after switching until the old log is clean and truncated.

Possible values:
	0		sl_log_1 active, sl_log_2 clean
	1		sl_log_2 active, sl_log_1 clean
	2		sl_log_1 active, sl_log_2 unknown - cleanup
	3		sl_log_2 active, sl_log_1 unknown - cleanup

This is not yet in use.
';


--
-- Name: sl_node; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_node (
    no_id integer NOT NULL,
    no_active boolean,
    no_comment text,
    no_failed boolean
);


ALTER TABLE _primer_cluster2.sl_node OWNER TO postgres;

--
-- Name: TABLE sl_node; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_node IS 'Holds the list of nodes associated with this namespace.';


--
-- Name: COLUMN sl_node.no_id; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_node.no_id IS 'The unique ID number for the node';


--
-- Name: COLUMN sl_node.no_active; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_node.no_active IS 'Is the node active in replication yet?';


--
-- Name: COLUMN sl_node.no_comment; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_node.no_comment IS 'A human-oriented description of the node';


--
-- Name: sl_nodelock; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_nodelock (
    nl_nodeid integer NOT NULL,
    nl_conncnt integer NOT NULL,
    nl_backendpid integer
);


ALTER TABLE _primer_cluster2.sl_nodelock OWNER TO postgres;

--
-- Name: TABLE sl_nodelock; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_nodelock IS 'Used to prevent multiple slon instances and to identify the backends to kill in terminateNodeConnections().';


--
-- Name: COLUMN sl_nodelock.nl_nodeid; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_nodelock.nl_nodeid IS 'Clients node_id';


--
-- Name: COLUMN sl_nodelock.nl_conncnt; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_nodelock.nl_conncnt IS 'Clients connection number';


--
-- Name: COLUMN sl_nodelock.nl_backendpid; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_nodelock.nl_backendpid IS 'PID of database backend owning this lock';


--
-- Name: sl_nodelock_nl_conncnt_seq; Type: SEQUENCE; Schema: _primer_cluster2; Owner: postgres
--

CREATE SEQUENCE _primer_cluster2.sl_nodelock_nl_conncnt_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE _primer_cluster2.sl_nodelock_nl_conncnt_seq OWNER TO postgres;

--
-- Name: sl_nodelock_nl_conncnt_seq; Type: SEQUENCE OWNED BY; Schema: _primer_cluster2; Owner: postgres
--

ALTER SEQUENCE _primer_cluster2.sl_nodelock_nl_conncnt_seq OWNED BY _primer_cluster2.sl_nodelock.nl_conncnt;


--
-- Name: sl_registry; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_registry (
    reg_key text NOT NULL,
    reg_int4 integer,
    reg_text text,
    reg_timestamp timestamp with time zone
);


ALTER TABLE _primer_cluster2.sl_registry OWNER TO postgres;

--
-- Name: TABLE sl_registry; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_registry IS 'Stores miscellaneous runtime data';


--
-- Name: COLUMN sl_registry.reg_key; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_registry.reg_key IS 'Unique key of the runtime option';


--
-- Name: COLUMN sl_registry.reg_int4; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_registry.reg_int4 IS 'Option value if type int4';


--
-- Name: COLUMN sl_registry.reg_text; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_registry.reg_text IS 'Option value if type text';


--
-- Name: COLUMN sl_registry.reg_timestamp; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_registry.reg_timestamp IS 'Option value if type timestamp';


--
-- Name: sl_sequence; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_sequence (
    seq_id integer NOT NULL,
    seq_reloid oid NOT NULL,
    seq_relname name NOT NULL,
    seq_nspname name NOT NULL,
    seq_set integer,
    seq_comment text
);


ALTER TABLE _primer_cluster2.sl_sequence OWNER TO postgres;

--
-- Name: TABLE sl_sequence; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_sequence IS 'Similar to sl_table, each entry identifies a sequence being replicated.';


--
-- Name: COLUMN sl_sequence.seq_id; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_sequence.seq_id IS 'An internally-used ID for Slony-I to use in its sequencing of updates';


--
-- Name: COLUMN sl_sequence.seq_reloid; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_sequence.seq_reloid IS 'The OID of the sequence object';


--
-- Name: COLUMN sl_sequence.seq_relname; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_sequence.seq_relname IS 'The name of the sequence in pg_catalog.pg_class.relname used to recover from a dump/restore cycle';


--
-- Name: COLUMN sl_sequence.seq_nspname; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_sequence.seq_nspname IS 'The name of the schema in pg_catalog.pg_namespace.nspname used to recover from a dump/restore cycle';


--
-- Name: COLUMN sl_sequence.seq_set; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_sequence.seq_set IS 'Indicates which replication set the object is in';


--
-- Name: COLUMN sl_sequence.seq_comment; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_sequence.seq_comment IS 'A human-oriented comment';


--
-- Name: sl_seqlastvalue; Type: VIEW; Schema: _primer_cluster2; Owner: postgres
--

CREATE VIEW _primer_cluster2.sl_seqlastvalue AS
 SELECT sq.seq_id,
    sq.seq_set,
    sq.seq_reloid,
    s.set_origin AS seq_origin,
    _primer_cluster2.sequencelastvalue(((quote_ident((pgn.nspname)::text) || '.'::text) || quote_ident((pgc.relname)::text))) AS seq_last_value
   FROM _primer_cluster2.sl_sequence sq,
    _primer_cluster2.sl_set s,
    pg_class pgc,
    pg_namespace pgn
  WHERE ((s.set_id = sq.seq_set) AND (pgc.oid = sq.seq_reloid) AND (pgn.oid = pgc.relnamespace));


ALTER TABLE _primer_cluster2.sl_seqlastvalue OWNER TO postgres;

--
-- Name: sl_seqlog; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_seqlog (
    seql_seqid integer,
    seql_origin integer,
    seql_ev_seqno bigint,
    seql_last_value bigint
);


ALTER TABLE _primer_cluster2.sl_seqlog OWNER TO postgres;

--
-- Name: TABLE sl_seqlog; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_seqlog IS 'Log of Sequence updates';


--
-- Name: COLUMN sl_seqlog.seql_seqid; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_seqlog.seql_seqid IS 'Sequence ID';


--
-- Name: COLUMN sl_seqlog.seql_origin; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_seqlog.seql_origin IS 'Publisher node at which the sequence originates';


--
-- Name: COLUMN sl_seqlog.seql_ev_seqno; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_seqlog.seql_ev_seqno IS 'Slony-I Event with which this sequence update is associated';


--
-- Name: COLUMN sl_seqlog.seql_last_value; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_seqlog.seql_last_value IS 'Last value published for this sequence';


--
-- Name: sl_setsync; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_setsync (
    ssy_setid integer NOT NULL,
    ssy_origin integer,
    ssy_seqno bigint,
    ssy_snapshot txid_snapshot,
    ssy_action_list text
);


ALTER TABLE _primer_cluster2.sl_setsync OWNER TO postgres;

--
-- Name: TABLE sl_setsync; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_setsync IS 'SYNC information';


--
-- Name: COLUMN sl_setsync.ssy_setid; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_setsync.ssy_setid IS 'ID number of the replication set';


--
-- Name: COLUMN sl_setsync.ssy_origin; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_setsync.ssy_origin IS 'ID number of the node';


--
-- Name: COLUMN sl_setsync.ssy_seqno; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_setsync.ssy_seqno IS 'Slony-I sequence number';


--
-- Name: COLUMN sl_setsync.ssy_snapshot; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_setsync.ssy_snapshot IS 'TXID in provider system seen by the event';


--
-- Name: COLUMN sl_setsync.ssy_action_list; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_setsync.ssy_action_list IS 'action list used during the subscription process. At the time a subscriber copies over data from the origin, it sees all tables in a state somewhere between two SYNC events. Therefore this list must contains all log_actionseqs that are visible at that time, whose operations have therefore already been included in the data copied at the time the initial data copy is done.  Those actions may therefore be filtered out of the first SYNC done after subscribing.';


--
-- Name: sl_status; Type: VIEW; Schema: _primer_cluster2; Owner: postgres
--

CREATE VIEW _primer_cluster2.sl_status AS
 SELECT e.ev_origin AS st_origin,
    c.con_received AS st_received,
    e.ev_seqno AS st_last_event,
    e.ev_timestamp AS st_last_event_ts,
    c.con_seqno AS st_last_received,
    c.con_timestamp AS st_last_received_ts,
    ce.ev_timestamp AS st_last_received_event_ts,
    (e.ev_seqno - c.con_seqno) AS st_lag_num_events,
    (CURRENT_TIMESTAMP - ce.ev_timestamp) AS st_lag_time
   FROM _primer_cluster2.sl_event e,
    _primer_cluster2.sl_confirm c,
    _primer_cluster2.sl_event ce
  WHERE ((e.ev_origin = c.con_origin) AND (ce.ev_origin = e.ev_origin) AND (ce.ev_seqno = c.con_seqno) AND ((e.ev_origin, e.ev_seqno) IN ( SELECT sl_event.ev_origin,
            max(sl_event.ev_seqno) AS max
           FROM _primer_cluster2.sl_event
          WHERE (sl_event.ev_origin = _primer_cluster2.getlocalnodeid('_primer_cluster2'::name))
          GROUP BY sl_event.ev_origin)) AND ((c.con_origin, c.con_received, c.con_seqno) IN ( SELECT sl_confirm.con_origin,
            sl_confirm.con_received,
            max(sl_confirm.con_seqno) AS max
           FROM _primer_cluster2.sl_confirm
          WHERE (sl_confirm.con_origin = _primer_cluster2.getlocalnodeid('_primer_cluster2'::name))
          GROUP BY sl_confirm.con_origin, sl_confirm.con_received)));


ALTER TABLE _primer_cluster2.sl_status OWNER TO postgres;

--
-- Name: VIEW sl_status; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON VIEW _primer_cluster2.sl_status IS 'View showing how far behind remote nodes are.';


--
-- Name: sl_table; Type: TABLE; Schema: _primer_cluster2; Owner: postgres
--

CREATE TABLE _primer_cluster2.sl_table (
    tab_id integer NOT NULL,
    tab_reloid oid NOT NULL,
    tab_relname name NOT NULL,
    tab_nspname name NOT NULL,
    tab_set integer,
    tab_idxname name NOT NULL,
    tab_altered boolean NOT NULL,
    tab_comment text
);


ALTER TABLE _primer_cluster2.sl_table OWNER TO postgres;

--
-- Name: TABLE sl_table; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON TABLE _primer_cluster2.sl_table IS 'Holds information about the tables being replicated.';


--
-- Name: COLUMN sl_table.tab_id; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_table.tab_id IS 'Unique key for Slony-I to use to identify the table';


--
-- Name: COLUMN sl_table.tab_reloid; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_table.tab_reloid IS 'The OID of the table in pg_catalog.pg_class.oid';


--
-- Name: COLUMN sl_table.tab_relname; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_table.tab_relname IS 'The name of the table in pg_catalog.pg_class.relname used to recover from a dump/restore cycle';


--
-- Name: COLUMN sl_table.tab_nspname; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_table.tab_nspname IS 'The name of the schema in pg_catalog.pg_namespace.nspname used to recover from a dump/restore cycle';


--
-- Name: COLUMN sl_table.tab_set; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_table.tab_set IS 'ID of the replication set the table is in';


--
-- Name: COLUMN sl_table.tab_idxname; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_table.tab_idxname IS 'The name of the primary index of the table';


--
-- Name: COLUMN sl_table.tab_altered; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_table.tab_altered IS 'Has the table been modified for replication?';


--
-- Name: COLUMN sl_table.tab_comment; Type: COMMENT; Schema: _primer_cluster2; Owner: postgres
--

COMMENT ON COLUMN _primer_cluster2.sl_table.tab_comment IS 'Human-oriented description of the table';


--
-- Name: agente; Type: TABLE; Schema: comercial; Owner: postgres
--

CREATE TABLE comercial.agente (
    id bigint NOT NULL,
    apellido_paterno character varying(45),
    apellido_materno character varying(45),
    nombre character varying(45),
    rfc character varying(13),
    zona_id bigint
);


ALTER TABLE comercial.agente OWNER TO postgres;

--
-- Name: agente_id_seq; Type: SEQUENCE; Schema: comercial; Owner: postgres
--

CREATE SEQUENCE comercial.agente_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE comercial.agente_id_seq OWNER TO postgres;

--
-- Name: agente_id_seq; Type: SEQUENCE OWNED BY; Schema: comercial; Owner: postgres
--

ALTER SEQUENCE comercial.agente_id_seq OWNED BY comercial.agente.id;


--
-- Name: comisiones; Type: TABLE; Schema: comercial; Owner: postgres
--

CREATE TABLE comercial.comisiones (
    id bigint NOT NULL,
    venta_id bigint,
    agente_id bigint,
    total numeric(14,4),
    comisionescol character varying(45)
);


ALTER TABLE comercial.comisiones OWNER TO postgres;

--
-- Name: comisiones_id_seq; Type: SEQUENCE; Schema: comercial; Owner: postgres
--

CREATE SEQUENCE comercial.comisiones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE comercial.comisiones_id_seq OWNER TO postgres;

--
-- Name: comisiones_id_seq; Type: SEQUENCE OWNED BY; Schema: comercial; Owner: postgres
--

ALTER SEQUENCE comercial.comisiones_id_seq OWNED BY comercial.comisiones.id;


--
-- Name: detalleventa; Type: TABLE; Schema: comercial; Owner: postgres
--

CREATE TABLE comercial.detalleventa (
    id bigint NOT NULL,
    detalle_venta_id bigint,
    producto_id bigint,
    cantidad numeric(14,4),
    precio numeric(14,4),
    tasa_iva_id bigint
);


ALTER TABLE comercial.detalleventa OWNER TO postgres;

--
-- Name: detalleventa_id_seq; Type: SEQUENCE; Schema: comercial; Owner: postgres
--

CREATE SEQUENCE comercial.detalleventa_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE comercial.detalleventa_id_seq OWNER TO postgres;

--
-- Name: detalleventa_id_seq; Type: SEQUENCE OWNED BY; Schema: comercial; Owner: postgres
--

ALTER SEQUENCE comercial.detalleventa_id_seq OWNED BY comercial.detalleventa.id;


--
-- Name: venta; Type: TABLE; Schema: comercial; Owner: postgres
--

CREATE TABLE comercial.venta (
    id bigint NOT NULL,
    folio bigint,
    fecha date,
    cliente_id bigint,
    agente_id bigint,
    estatus bigint
);


ALTER TABLE comercial.venta OWNER TO postgres;

--
-- Name: venta_id_seq; Type: SEQUENCE; Schema: comercial; Owner: postgres
--

CREATE SEQUENCE comercial.venta_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE comercial.venta_id_seq OWNER TO postgres;

--
-- Name: venta_id_seq; Type: SEQUENCE OWNED BY; Schema: comercial; Owner: postgres
--

ALTER SEQUENCE comercial.venta_id_seq OWNED BY comercial.venta.id;


--
-- Name: clientes; Type: TABLE; Schema: cxc; Owner: postgres
--

CREATE TABLE cxc.clientes (
    id bigint NOT NULL,
    nombre character varying(45),
    apellido_paterno character varying(45),
    apellido_materno character varying(45),
    rfc character varying(13),
    agente_id bigint
);


ALTER TABLE cxc.clientes OWNER TO postgres;

--
-- Name: clientes_id_seq; Type: SEQUENCE; Schema: cxc; Owner: postgres
--

CREATE SEQUENCE cxc.clientes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE cxc.clientes_id_seq OWNER TO postgres;

--
-- Name: clientes_id_seq; Type: SEQUENCE OWNED BY; Schema: cxc; Owner: postgres
--

ALTER SEQUENCE cxc.clientes_id_seq OWNED BY cxc.clientes.id;


--
-- Name: clientes_impar; Type: TABLE; Schema: cxc; Owner: postgres
--

CREATE TABLE cxc.clientes_impar (
    CONSTRAINT clientes_impar_id_check CHECK (((id % (2)::bigint) <> 0))
)
INHERITS (cxc.clientes);


ALTER TABLE cxc.clientes_impar OWNER TO postgres;

--
-- Name: clientes_par; Type: TABLE; Schema: cxc; Owner: postgres
--

CREATE TABLE cxc.clientes_par (
    CONSTRAINT clientes_par_id_check CHECK (((id % (2)::bigint) = 0))
)
INHERITS (cxc.clientes);


ALTER TABLE cxc.clientes_par OWNER TO postgres;

--
-- Name: cuentasporcobrar; Type: TABLE; Schema: cxc; Owner: postgres
--

CREATE TABLE cxc.cuentasporcobrar (
    id bigint NOT NULL,
    folio integer,
    cliente_id bigint,
    venta_id bigint,
    total numeric(14,4),
    saldo numeric(14,4)
);


ALTER TABLE cxc.cuentasporcobrar OWNER TO postgres;

--
-- Name: cuentasporcobrar_id_seq; Type: SEQUENCE; Schema: cxc; Owner: postgres
--

CREATE SEQUENCE cxc.cuentasporcobrar_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE cxc.cuentasporcobrar_id_seq OWNER TO postgres;

--
-- Name: cuentasporcobrar_id_seq; Type: SEQUENCE OWNED BY; Schema: cxc; Owner: postgres
--

ALTER SEQUENCE cxc.cuentasporcobrar_id_seq OWNED BY cxc.cuentasporcobrar.id;


--
-- Name: movimientoscxc; Type: TABLE; Schema: cxc; Owner: postgres
--

CREATE TABLE cxc.movimientoscxc (
    id bigint NOT NULL,
    tipo_movimiento_id bigint,
    folio integer,
    fecha date,
    importe numeric(14,4),
    naturaleza character(1),
    cxc_id bigint
);


ALTER TABLE cxc.movimientoscxc OWNER TO postgres;

--
-- Name: movimientoscxc_id_seq; Type: SEQUENCE; Schema: cxc; Owner: postgres
--

CREATE SEQUENCE cxc.movimientoscxc_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE cxc.movimientoscxc_id_seq OWNER TO postgres;

--
-- Name: movimientoscxc_id_seq; Type: SEQUENCE OWNED BY; Schema: cxc; Owner: postgres
--

ALTER SEQUENCE cxc.movimientoscxc_id_seq OWNED BY cxc.movimientoscxc.id;


--
-- Name: tipomovimientocxc; Type: TABLE; Schema: cxc; Owner: postgres
--

CREATE TABLE cxc.tipomovimientocxc (
    id bigint NOT NULL,
    nombre character varying(45),
    naturaleza integer
);


ALTER TABLE cxc.tipomovimientocxc OWNER TO postgres;

--
-- Name: tipomovimientocxc_id_seq; Type: SEQUENCE; Schema: cxc; Owner: postgres
--

CREATE SEQUENCE cxc.tipomovimientocxc_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE cxc.tipomovimientocxc_id_seq OWNER TO postgres;

--
-- Name: tipomovimientocxc_id_seq; Type: SEQUENCE OWNED BY; Schema: cxc; Owner: postgres
--

ALTER SEQUENCE cxc.tipomovimientocxc_id_seq OWNED BY cxc.tipomovimientocxc.id;


--
-- Name: movimientoinventario; Type: TABLE; Schema: inventarios; Owner: postgres
--

CREATE TABLE inventarios.movimientoinventario (
    id bigint NOT NULL,
    folio integer,
    producto_id bigint,
    fecha integer,
    cantidad numeric(14,4),
    naturaleza integer,
    tipo_movimiento_id bigint,
    movimientoinventariocol character varying(45),
    almacen_id bigint,
    movimientoinventariocol1 character varying(45)
);


ALTER TABLE inventarios.movimientoinventario OWNER TO postgres;

--
-- Name: movimientoinventario_id_seq; Type: SEQUENCE; Schema: inventarios; Owner: postgres
--

CREATE SEQUENCE inventarios.movimientoinventario_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE inventarios.movimientoinventario_id_seq OWNER TO postgres;

--
-- Name: movimientoinventario_id_seq; Type: SEQUENCE OWNED BY; Schema: inventarios; Owner: postgres
--

ALTER SEQUENCE inventarios.movimientoinventario_id_seq OWNED BY inventarios.movimientoinventario.id;


--
-- Name: producto; Type: TABLE; Schema: inventarios; Owner: postgres
--

CREATE TABLE inventarios.producto (
    id bigint NOT NULL,
    nombre character varying(45)
);


ALTER TABLE inventarios.producto OWNER TO postgres;

--
-- Name: producto_id_seq; Type: SEQUENCE; Schema: inventarios; Owner: postgres
--

CREATE SEQUENCE inventarios.producto_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE inventarios.producto_id_seq OWNER TO postgres;

--
-- Name: producto_id_seq; Type: SEQUENCE OWNED BY; Schema: inventarios; Owner: postgres
--

ALTER SEQUENCE inventarios.producto_id_seq OWNED BY inventarios.producto.id;


--
-- Name: tipomovimiento; Type: TABLE; Schema: inventarios; Owner: postgres
--

CREATE TABLE inventarios.tipomovimiento (
    id integer NOT NULL,
    nombre character varying(45),
    naturaleza integer
);


ALTER TABLE inventarios.tipomovimiento OWNER TO postgres;

--
-- Name: sl_nodelock nl_conncnt; Type: DEFAULT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_nodelock ALTER COLUMN nl_conncnt SET DEFAULT nextval('_primer_cluster2.sl_nodelock_nl_conncnt_seq'::regclass);


--
-- Name: agente id; Type: DEFAULT; Schema: comercial; Owner: postgres
--

ALTER TABLE ONLY comercial.agente ALTER COLUMN id SET DEFAULT nextval('comercial.agente_id_seq'::regclass);


--
-- Name: comisiones id; Type: DEFAULT; Schema: comercial; Owner: postgres
--

ALTER TABLE ONLY comercial.comisiones ALTER COLUMN id SET DEFAULT nextval('comercial.comisiones_id_seq'::regclass);


--
-- Name: detalleventa id; Type: DEFAULT; Schema: comercial; Owner: postgres
--

ALTER TABLE ONLY comercial.detalleventa ALTER COLUMN id SET DEFAULT nextval('comercial.detalleventa_id_seq'::regclass);


--
-- Name: venta id; Type: DEFAULT; Schema: comercial; Owner: postgres
--

ALTER TABLE ONLY comercial.venta ALTER COLUMN id SET DEFAULT nextval('comercial.venta_id_seq'::regclass);


--
-- Name: clientes id; Type: DEFAULT; Schema: cxc; Owner: postgres
--

ALTER TABLE ONLY cxc.clientes ALTER COLUMN id SET DEFAULT nextval('cxc.clientes_id_seq'::regclass);


--
-- Name: clientes_impar id; Type: DEFAULT; Schema: cxc; Owner: postgres
--

ALTER TABLE ONLY cxc.clientes_impar ALTER COLUMN id SET DEFAULT nextval('cxc.clientes_id_seq'::regclass);


--
-- Name: clientes_par id; Type: DEFAULT; Schema: cxc; Owner: postgres
--

ALTER TABLE ONLY cxc.clientes_par ALTER COLUMN id SET DEFAULT nextval('cxc.clientes_id_seq'::regclass);


--
-- Name: cuentasporcobrar id; Type: DEFAULT; Schema: cxc; Owner: postgres
--

ALTER TABLE ONLY cxc.cuentasporcobrar ALTER COLUMN id SET DEFAULT nextval('cxc.cuentasporcobrar_id_seq'::regclass);


--
-- Name: movimientoscxc id; Type: DEFAULT; Schema: cxc; Owner: postgres
--

ALTER TABLE ONLY cxc.movimientoscxc ALTER COLUMN id SET DEFAULT nextval('cxc.movimientoscxc_id_seq'::regclass);


--
-- Name: tipomovimientocxc id; Type: DEFAULT; Schema: cxc; Owner: postgres
--

ALTER TABLE ONLY cxc.tipomovimientocxc ALTER COLUMN id SET DEFAULT nextval('cxc.tipomovimientocxc_id_seq'::regclass);


--
-- Name: movimientoinventario id; Type: DEFAULT; Schema: inventarios; Owner: postgres
--

ALTER TABLE ONLY inventarios.movimientoinventario ALTER COLUMN id SET DEFAULT nextval('inventarios.movimientoinventario_id_seq'::regclass);


--
-- Name: producto id; Type: DEFAULT; Schema: inventarios; Owner: postgres
--

ALTER TABLE ONLY inventarios.producto ALTER COLUMN id SET DEFAULT nextval('inventarios.producto_id_seq'::regclass);


--
-- Data for Name: sl_apply_stats; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_apply_stats (as_origin, as_num_insert, as_num_update, as_num_delete, as_num_truncate, as_num_script, as_num_total, as_duration, as_apply_first, as_apply_last, as_cache_prepare, as_cache_hit, as_cache_evict, as_cache_prepare_max) FROM stdin;
2	0	0	0	0	0	0	00:00:00.376	2018-06-06 11:26:01.259959-06	2018-06-06 12:06:07.901275-06	0	0	0	0
\.


--
-- Data for Name: sl_archive_counter; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_archive_counter (ac_num, ac_timestamp) FROM stdin;
0	1969-12-31 18:00:00-06
\.


--
-- Data for Name: sl_components; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_components (co_actor, co_pid, co_node, co_connection_pid, co_activity, co_starttime, co_event, co_eventtype) FROM stdin;
local_monitor	12576	0	14616	thread main loop	2018-06-06 11:25:23-06	\N	n/a
remote listener	12576	2	8188	thread main loop	2018-06-06 12:06:15-06	\N	n/a
local_listen	12576	1	14312	thread main loop	2018-06-06 12:06:21-06	\N	n/a
local_sync	12576	0	12704	thread main loop	2018-06-06 12:06:21-06	\N	n/a
local_cleanup	12576	0	5660	cleanupEvent	2018-06-06 12:05:25-06	\N	n/a
remoteWorkerThread_2	12576	2	5908	SYNC	2018-06-06 12:06:08-06	5000000241	SYNC
\.


--
-- Data for Name: sl_config_lock; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_config_lock (dummy) FROM stdin;
\.


--
-- Data for Name: sl_confirm; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_confirm (con_origin, con_received, con_seqno, con_timestamp) FROM stdin;
2	1	5000000182	2018-06-06 11:56:15.27766-06
2	1	5000000183	2018-06-06 11:56:33.292301-06
1	2	5000000006	2018-06-06 11:24:51.220803-06
2	1	5000000184	2018-06-06 11:56:35.298586-06
2	1	5000000185	2018-06-06 11:56:53.309942-06
2	1	5000000186	2018-06-06 11:56:55.312086-06
2	1	5000000187	2018-06-06 11:57:13.321577-06
2	1	5000000188	2018-06-06 11:57:15.32743-06
2	1	5000000189	2018-06-06 11:57:33.357371-06
2	1	5000000190	2018-06-06 11:57:35.364996-06
2	1	5000000191	2018-06-06 11:57:53.389224-06
2	1	5000000192	2018-06-06 11:57:55.383421-06
2	1	5000000193	2018-06-06 11:58:13.406196-06
2	1	5000000194	2018-06-06 11:58:15.414286-06
2	1	5000000195	2018-06-06 11:58:33.442084-06
2	1	5000000196	2018-06-06 11:58:35.458236-06
2	1	5000000197	2018-06-06 11:58:53.454027-06
2	1	5000000198	2018-06-06 11:59:01.462864-06
2	1	5000000199	2018-06-06 11:59:09.479047-06
2	1	5000000200	2018-06-06 11:59:17.493206-06
2	1	5000000201	2018-06-06 11:59:35.519551-06
2	1	5000000202	2018-06-06 11:59:37.521616-06
2	1	5000000203	2018-06-06 11:59:55.53771-06
2	1	5000000204	2018-06-06 11:59:57.552136-06
2	1	5000000205	2018-06-06 12:00:15.575251-06
2	1	5000000206	2018-06-06 12:00:17.58908-06
2	1	5000000207	2018-06-06 12:00:35.597856-06
2	1	5000000208	2018-06-06 12:00:37.607052-06
2	1	5000000209	2018-06-06 12:00:55.610293-06
2	1	5000000210	2018-06-06 12:00:57.617678-06
2	1	5000000211	2018-06-06 12:01:15.640129-06
2	1	5000000212	2018-06-06 12:01:17.650794-06
2	1	5000000213	2018-06-06 12:01:35.676688-06
2	1	5000000214	2018-06-06 12:01:37.661472-06
2	1	5000000215	2018-06-06 12:01:55.680942-06
2	1	5000000216	2018-06-06 12:01:57.690571-06
2	1	5000000217	2018-06-06 12:02:15.680047-06
2	1	5000000218	2018-06-06 12:02:17.688518-06
2	1	5000000219	2018-06-06 12:02:35.733743-06
2	1	5000000220	2018-06-06 12:02:37.749437-06
2	1	5000000221	2018-06-06 12:02:55.747628-06
2	1	5000000222	2018-06-06 12:02:57.748748-06
2	1	5000000223	2018-06-06 12:03:15.74808-06
2	1	5000000224	2018-06-06 12:03:17.749341-06
2	1	5000000225	2018-06-06 12:03:35.753722-06
2	1	5000000226	2018-06-06 12:03:37.754878-06
2	1	5000000227	2018-06-06 12:03:55.752302-06
2	1	5000000228	2018-06-06 12:03:57.754724-06
2	1	5000000229	2018-06-06 12:04:15.762977-06
2	1	5000000230	2018-06-06 12:04:17.764175-06
2	1	5000000231	2018-06-06 12:04:35.771443-06
2	1	5000000232	2018-06-06 12:04:37.768983-06
2	1	5000000233	2018-06-06 12:04:55.785182-06
2	1	5000000234	2018-06-06 12:04:57.786463-06
2	1	5000000235	2018-06-06 12:05:15.784641-06
2	1	5000000236	2018-06-06 12:05:23.800705-06
2	1	5000000237	2018-06-06 12:05:31.818346-06
2	1	5000000238	2018-06-06 12:05:39.835388-06
2	1	5000000239	2018-06-06 12:05:47.850352-06
2	1	5000000240	2018-06-06 12:06:05.885235-06
2	1	5000000241	2018-06-06 12:06:07.899331-06
2	1	5000000176	2018-06-06 11:55:15.226899-06
2	1	5000000177	2018-06-06 11:55:33.255287-06
2	1	5000000178	2018-06-06 11:55:35.257189-06
2	1	5000000179	2018-06-06 11:55:53.278446-06
2	1	5000000180	2018-06-06 11:55:55.26329-06
2	1	5000000181	2018-06-06 11:56:13.278212-06
\.


--
-- Data for Name: sl_event; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_event (ev_origin, ev_seqno, ev_timestamp, ev_snapshot, ev_type, ev_data1, ev_data2, ev_data3, ev_data4, ev_data5, ev_data6, ev_data7, ev_data8) FROM stdin;
2	5000000182	2018-06-06 11:56:14.749531-06	6333:6336:6333,6334	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000183	2018-06-06 11:56:25.003339-06	6363:6363:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000184	2018-06-06 11:56:35.050449-06	6388:6388:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000185	2018-06-06 11:56:45.063414-06	6414:6414:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000005	2018-06-06 11:24:50.766212-06	1792:1792:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000006	2018-06-06 11:24:50.766721-06	1793:1793:	SET_ADD_TABLE	1	2	cxc.clientes	pk_clientes	agentes	\N	\N	\N
1	5000000007	2018-06-06 11:24:50.781063-06	1794:1794:	STORE_NODE	2	Nodo Esclavo	\N	\N	\N	\N	\N	\N
1	5000000008	2018-06-06 11:24:50.781063-06	1794:1794:	ENABLE_NODE	2	\N	\N	\N	\N	\N	\N	\N
1	5000000009	2018-06-06 11:24:51.245982-06	1796:1796:	STORE_PATH	1	1	dbname = launica port = 5030 host =localhost user = postgres password=clickbalance123	10	\N	\N	\N	\N
1	5000000010	2018-06-06 11:24:51.252893-06	1797:1797:	STORE_PATH	2	1	dbname = postgres port = 5030 host =localhost user = postgres password=clickbalance123	10	\N	\N	\N	\N
1	5000000011	2018-06-06 11:25:09.959444-06	1805:1805:	SUBSCRIBE_SET	1	1	2	f	f	\N	\N	\N
1	5000000012	2018-06-06 11:25:09.959444-06	1805:1805:	ENABLE_SUBSCRIPTION	1	1	2	f	f	\N	\N	\N
1	5000000013	2018-06-06 11:25:25.291162-06	1812:1812:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000014	2018-06-06 11:25:35.305004-06	1822:1822:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000015	2018-06-06 11:25:45.308918-06	1832:1832:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000016	2018-06-06 11:25:55.311321-06	1844:1844:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000186	2018-06-06 11:56:55.099384-06	6437:6437:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000017	2018-06-06 11:26:05.315064-06	1866:1866:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000187	2018-06-06 11:57:05.136929-06	6462:6462:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000018	2018-06-06 11:26:15.319327-06	1888:1888:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000188	2018-06-06 11:57:15.170692-06	6487:6487:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000019	2018-06-06 11:26:25.323616-06	1909:1909:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000189	2018-06-06 11:57:25.193293-06	6510:6510:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000020	2018-06-06 11:26:35.327575-06	1930:1930:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000190	2018-06-06 11:57:35.255256-06	6534:6534:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000021	2018-06-06 11:26:45.329704-06	1951:1951:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000191	2018-06-06 11:57:45.294274-06	6561:6561:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000022	2018-06-06 11:26:55.340181-06	1973:1973:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000192	2018-06-06 11:57:55.320393-06	6585:6585:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000023	2018-06-06 11:27:05.370834-06	1994:1994:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000193	2018-06-06 11:58:05.346488-06	6610:6610:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000024	2018-06-06 11:27:15.37505-06	2016:2016:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000194	2018-06-06 11:58:15.382537-06	6635:6635:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000025	2018-06-06 11:27:25.377404-06	2037:2037:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000195	2018-06-06 11:58:25.41956-06	6660:6660:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000026	2018-06-06 11:27:35.381991-06	2058:2058:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000196	2018-06-06 11:58:35.442158-06	6685:6685:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000027	2018-06-06 11:27:45.385421-06	2079:2079:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000197	2018-06-06 11:58:45.492193-06	6708:6708:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000028	2018-06-06 11:27:55.390361-06	2100:2100:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000198	2018-06-06 11:58:55.53881-06	6729:6729:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000029	2018-06-06 11:28:05.394506-06	2121:2121:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000199	2018-06-06 11:59:05.575772-06	6751:6751:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000030	2018-06-06 11:28:15.402752-06	2148:2148:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000200	2018-06-06 11:59:15.631191-06	6774:6774:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000031	2018-06-06 11:28:25.421036-06	2169:2169:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000201	2018-06-06 11:59:25.680536-06	6800:6800:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000032	2018-06-06 11:28:35.425693-06	2190:2190:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000202	2018-06-06 11:59:35.737777-06	6827:6827:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000033	2018-06-06 11:28:45.438197-06	2213:2213:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000203	2018-06-06 11:59:45.746438-06	6854:6854:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000034	2018-06-06 11:28:55.48067-06	2240:2240:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000204	2018-06-06 11:59:55.751533-06	6877:6877:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000035	2018-06-06 11:29:05.508467-06	2265:2265:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000205	2018-06-06 12:00:05.780169-06	6898:6898:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000036	2018-06-06 11:29:15.541992-06	2292:2292:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000206	2018-06-06 12:00:15.794331-06	6919:6919:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000037	2018-06-06 11:29:25.557064-06	2315:2315:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000207	2018-06-06 12:00:25.825321-06	6940:6940:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000038	2018-06-06 11:29:35.574637-06	2338:2338:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000208	2018-06-06 12:00:35.848225-06	6960:6960:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000039	2018-06-06 11:29:45.605595-06	2359:2359:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000209	2018-06-06 12:00:46.914341-06	6984:6984:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000040	2018-06-06 11:29:55.630026-06	2380:2380:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000210	2018-06-06 12:00:56.964519-06	7007:7007:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000041	2018-06-06 11:30:05.657994-06	2401:2401:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000211	2018-06-06 12:01:06.982043-06	7030:7030:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000042	2018-06-06 11:30:15.69793-06	2423:2423:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000212	2018-06-06 12:01:17.012768-06	7055:7055:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000043	2018-06-06 11:30:25.746763-06	2444:2444:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000213	2018-06-06 12:01:27.047582-06	7080:7080:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000044	2018-06-06 11:30:35.75997-06	2468:2468:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000214	2018-06-06 12:01:37.09331-06	7106:7106:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000045	2018-06-06 11:30:45.786907-06	2494:2494:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000215	2018-06-06 12:01:47.132458-06	7131:7131:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000046	2018-06-06 11:30:55.788803-06	2522:2522:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000216	2018-06-06 12:01:57.155239-06	7155:7155:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000047	2018-06-06 11:31:05.791091-06	2548:2548:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000217	2018-06-06 12:02:07.184836-06	7178:7178:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000048	2018-06-06 11:31:15.795468-06	2575:2575:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000218	2018-06-06 12:02:17.207655-06	7203:7203:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000049	2018-06-06 11:31:25.80051-06	2602:2602:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000219	2018-06-06 12:02:27.234963-06	7227:7227:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000050	2018-06-06 11:31:35.861142-06	2628:2628:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000220	2018-06-06 12:02:37.269304-06	7250:7250:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000198	2018-06-06 11:56:22.456514-06	6357:6357:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000199	2018-06-06 11:56:32.502112-06	6381:6381:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000200	2018-06-06 11:56:42.543151-06	6408:6408:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000201	2018-06-06 11:56:52.585964-06	6431:6431:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000202	2018-06-06 11:57:02.597781-06	6457:6457:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000203	2018-06-06 11:57:12.651382-06	6479:6479:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000204	2018-06-06 11:57:22.693044-06	6505:6505:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000205	2018-06-06 11:57:32.742011-06	6527:6527:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000206	2018-06-06 11:57:42.746594-06	6554:6554:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000207	2018-06-06 11:57:52.752104-06	6577:6577:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000208	2018-06-06 11:58:02.769431-06	6603:6603:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000209	2018-06-06 11:58:12.81592-06	6626:6626:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000210	2018-06-06 11:58:22.857883-06	6653:6653:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000211	2018-06-06 11:58:32.890396-06	6677:6677:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000212	2018-06-06 11:58:42.905147-06	6703:6703:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000213	2018-06-06 11:58:52.952407-06	6723:6723:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000214	2018-06-06 11:59:02.987662-06	6746:6746:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000215	2018-06-06 11:59:12.989927-06	6767:6767:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000216	2018-06-06 11:59:23.02046-06	6794:6794:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000217	2018-06-06 11:59:33.069005-06	6820:6820:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000218	2018-06-06 11:59:43.106116-06	6847:6847:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000219	2018-06-06 11:59:53.14076-06	6870:6870:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000220	2018-06-06 12:00:03.153429-06	6892:6892:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000221	2018-06-06 12:00:13.182868-06	6912:6912:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000222	2018-06-06 12:00:23.2081-06	6935:6935:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000223	2018-06-06 12:00:33.239867-06	6955:6955:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000224	2018-06-06 12:00:43.295368-06	6977:6977:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000225	2018-06-06 12:00:53.339349-06	6998:6998:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000226	2018-06-06 12:01:03.368998-06	7023:7023:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000227	2018-06-06 12:01:13.411718-06	7046:7046:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000228	2018-06-06 12:01:23.422175-06	7071:7071:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000229	2018-06-06 12:01:33.453654-06	7096:7096:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000230	2018-06-06 12:01:43.469046-06	7123:7123:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000231	2018-06-06 12:01:53.498588-06	7146:7146:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000232	2018-06-06 12:02:03.533698-06	7170:7170:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000233	2018-06-06 12:02:13.574938-06	7193:7193:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000234	2018-06-06 12:02:23.628254-06	7220:7220:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000235	2018-06-06 12:02:33.654644-06	7242:7242:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000236	2018-06-06 12:02:43.701535-06	7267:7267:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000237	2018-06-06 12:02:53.746074-06	7290:7290:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000238	2018-06-06 12:03:03.735559-06	7314:7314:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000239	2018-06-06 12:03:13.748794-06	7337:7337:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000051	2018-06-06 11:31:45.893834-06	2656:2656:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000052	2018-06-06 11:31:55.937072-06	2681:2681:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000053	2018-06-06 11:32:05.94592-06	2704:2704:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000054	2018-06-06 11:32:15.979718-06	2727:2727:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000055	2018-06-06 11:32:26.011372-06	2749:2749:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000056	2018-06-06 11:32:36.031145-06	2770:2770:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000057	2018-06-06 11:32:46.065341-06	2791:2791:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000058	2018-06-06 11:32:56.086563-06	2818:2818:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000059	2018-06-06 11:33:06.092406-06	2845:2845:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000060	2018-06-06 11:33:16.099599-06	2871:2871:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000061	2018-06-06 11:33:26.107368-06	2898:2898:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000062	2018-06-06 11:33:36.115917-06	2925:2925:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000063	2018-06-06 11:33:46.12223-06	2950:2950:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000064	2018-06-06 11:33:56.127545-06	2977:2977:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000065	2018-06-06 11:34:06.133704-06	3003:3003:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000221	2018-06-06 12:02:47.327005-06	7274:7274:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000066	2018-06-06 11:34:16.139081-06	3033:3033:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000222	2018-06-06 12:02:57.357274-06	7299:7299:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000067	2018-06-06 11:34:26.11803-06	3060:3060:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000068	2018-06-06 11:34:36.122378-06	3086:3086:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000069	2018-06-06 11:34:46.123251-06	3112:3112:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000070	2018-06-06 11:34:56.126983-06	3142:3142:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000071	2018-06-06 11:35:06.128998-06	3168:3168:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000072	2018-06-06 11:35:16.130136-06	3196:3196:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000073	2018-06-06 11:35:26.133192-06	3225:3225:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000074	2018-06-06 11:35:36.137163-06	3251:3251:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000075	2018-06-06 11:35:46.141099-06	3278:3278:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000076	2018-06-06 11:35:56.144143-06	3306:3306:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000077	2018-06-06 11:36:06.147718-06	3332:3332:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000078	2018-06-06 11:36:16.148582-06	3359:3359:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000079	2018-06-06 11:36:26.150997-06	3386:3386:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000080	2018-06-06 11:36:36.154812-06	3412:3412:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000081	2018-06-06 11:36:46.15631-06	3438:3438:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000082	2018-06-06 11:36:56.159222-06	3466:3466:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000083	2018-06-06 11:37:06.1637-06	3492:3492:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000084	2018-06-06 11:37:16.163448-06	3519:3519:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000085	2018-06-06 11:37:26.166688-06	3546:3546:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000086	2018-06-06 11:37:36.170409-06	3572:3572:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000087	2018-06-06 11:37:46.174023-06	3598:3598:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000088	2018-06-06 11:37:56.174958-06	3625:3625:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000089	2018-06-06 11:38:06.178911-06	3651:3651:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000090	2018-06-06 11:38:16.18076-06	3678:3678:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000091	2018-06-06 11:38:26.183533-06	3705:3705:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000092	2018-06-06 11:38:36.186093-06	3731:3731:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000093	2018-06-06 11:38:46.199134-06	3756:3756:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000094	2018-06-06 11:38:56.201839-06	3782:3782:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000095	2018-06-06 11:39:06.206026-06	3807:3807:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000096	2018-06-06 11:39:16.209673-06	3833:3833:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000097	2018-06-06 11:39:26.213329-06	3858:3858:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000098	2018-06-06 11:39:36.216446-06	3882:3882:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000099	2018-06-06 11:39:46.218026-06	3908:3908:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000100	2018-06-06 11:39:56.260919-06	3933:3933:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000101	2018-06-06 11:40:06.260347-06	3957:3957:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000102	2018-06-06 11:40:16.306742-06	3980:3980:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000103	2018-06-06 11:40:26.353753-06	4004:4004:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000104	2018-06-06 11:40:36.403277-06	4028:4028:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000105	2018-06-06 11:40:46.42492-06	4051:4051:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000106	2018-06-06 11:40:56.452016-06	4078:4078:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000107	2018-06-06 11:41:06.48784-06	4104:4104:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000108	2018-06-06 11:41:16.51335-06	4132:4132:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000109	2018-06-06 11:41:26.545409-06	4160:4160:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000110	2018-06-06 11:41:36.574451-06	4186:4186:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000111	2018-06-06 11:41:46.626116-06	4213:4213:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000112	2018-06-06 11:41:56.669619-06	4238:4238:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000113	2018-06-06 11:42:06.693366-06	4265:4265:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000114	2018-06-06 11:42:16.748601-06	4289:4289:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000115	2018-06-06 11:42:26.795575-06	4315:4315:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000116	2018-06-06 11:42:36.827095-06	4342:4342:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000117	2018-06-06 11:42:46.858179-06	4370:4370:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000118	2018-06-06 11:42:56.904623-06	4399:4399:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000119	2018-06-06 11:43:06.934701-06	4424:4424:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000120	2018-06-06 11:43:16.983015-06	4449:4449:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000121	2018-06-06 11:43:27.028873-06	4474:4474:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000122	2018-06-06 11:43:37.073662-06	4501:4501:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000123	2018-06-06 11:43:47.074264-06	4529:4529:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000124	2018-06-06 11:43:57.13093-06	4557:4557:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000125	2018-06-06 11:44:07.17116-06	4585:4585:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000126	2018-06-06 11:44:17.226015-06	4614:4614:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000127	2018-06-06 11:44:27.29505-06	4639:4639:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000128	2018-06-06 11:44:38.388277-06	4663:4663:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000129	2018-06-06 11:44:48.423032-06	4685:4685:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000130	2018-06-06 11:44:58.452037-06	4707:4707:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000131	2018-06-06 11:45:08.456693-06	4729:4729:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000223	2018-06-06 12:03:07.389598-06	7322:7322:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000224	2018-06-06 12:03:17.41421-06	7348:7348:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000225	2018-06-06 12:03:27.443504-06	7369:7369:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000226	2018-06-06 12:03:37.484435-06	7390:7390:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000227	2018-06-06 12:03:47.523674-06	7412:7412:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000228	2018-06-06 12:03:57.551362-06	7436:7436:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000229	2018-06-06 12:04:07.601308-06	7459:7459:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000230	2018-06-06 12:04:17.645401-06	7483:7483:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000231	2018-06-06 12:04:27.677994-06	7504:7504:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000232	2018-06-06 12:04:37.700557-06	7525:7525:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000233	2018-06-06 12:04:47.743423-06	7546:7546:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000234	2018-06-06 12:04:57.749803-06	7571:7571:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000235	2018-06-06 12:05:07.760621-06	7594:7594:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000236	2018-06-06 12:05:17.79772-06	7619:7619:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000237	2018-06-06 12:05:27.784586-06	7646:7646:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000238	2018-06-06 12:05:37.800008-06	7669:7669:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000239	2018-06-06 12:05:47.818619-06	7690:7690:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000240	2018-06-06 12:05:57.843716-06	7713:7713:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000241	2018-06-06 12:06:07.836234-06	7735:7735:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000240	2018-06-06 12:03:23.751374-06	7362:7362:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000241	2018-06-06 12:03:33.76725-06	7382:7382:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000242	2018-06-06 12:03:43.765031-06	7404:7404:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000243	2018-06-06 12:03:53.772948-06	7427:7427:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000244	2018-06-06 12:04:03.768904-06	7451:7451:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000245	2018-06-06 12:04:13.780419-06	7474:7474:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000246	2018-06-06 12:04:23.779839-06	7497:7497:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000247	2018-06-06 12:04:33.77563-06	7517:7517:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000248	2018-06-06 12:04:43.771053-06	7539:7539:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000249	2018-06-06 12:04:53.797639-06	7561:7561:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000250	2018-06-06 12:05:03.801217-06	7586:7586:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000251	2018-06-06 12:05:13.801135-06	7609:7609:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000252	2018-06-06 12:05:23.800198-06	7634:7634:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000253	2018-06-06 12:05:33.818723-06	7661:7661:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000254	2018-06-06 12:05:43.847367-06	7683:7683:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000255	2018-06-06 12:05:53.888341-06	7704:7704:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000256	2018-06-06 12:06:03.890514-06	7727:7727:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000257	2018-06-06 12:06:13.912297-06	7751:7751:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000132	2018-06-06 11:45:18.485642-06	4753:4753:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000133	2018-06-06 11:45:28.505502-06	4774:4774:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000134	2018-06-06 11:45:38.563541-06	4796:4796:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000135	2018-06-06 11:45:49.748473-06	4821:4821:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000136	2018-06-06 11:46:00.08354-06	4849:4849:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000137	2018-06-06 11:46:10.108856-06	4869:4869:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000138	2018-06-06 11:46:20.130769-06	4893:4893:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000139	2018-06-06 11:46:30.630355-06	4913:4913:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000140	2018-06-06 11:46:40.665835-06	4935:4935:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000141	2018-06-06 11:46:50.676418-06	4956:4956:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000142	2018-06-06 11:47:00.703385-06	4982:4982:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000143	2018-06-06 11:47:10.708868-06	5004:5004:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000144	2018-06-06 11:47:20.71511-06	5029:5029:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000145	2018-06-06 11:47:30.72467-06	5049:5049:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000146	2018-06-06 11:47:40.739201-06	5074:5074:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000147	2018-06-06 11:47:50.740927-06	5094:5094:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000148	2018-06-06 11:48:00.746612-06	5118:5118:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000149	2018-06-06 11:48:10.748435-06	5141:5141:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000150	2018-06-06 11:48:20.748389-06	5167:5167:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000151	2018-06-06 11:48:30.751167-06	5189:5189:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000152	2018-06-06 11:48:40.753447-06	5214:5214:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000153	2018-06-06 11:48:50.760225-06	5239:5239:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000154	2018-06-06 11:49:00.785724-06	5262:5262:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000155	2018-06-06 11:49:10.799913-06	5282:5282:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000156	2018-06-06 11:49:20.816276-06	5305:5305:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000157	2018-06-06 11:49:30.831621-06	5325:5325:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000158	2018-06-06 11:49:40.82639-06	5349:5349:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000159	2018-06-06 11:49:50.876454-06	5373:5373:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000160	2018-06-06 11:50:00.907895-06	5398:5398:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000161	2018-06-06 11:50:10.955596-06	5420:5420:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000162	2018-06-06 11:50:20.979973-06	5442:5442:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000163	2018-06-06 11:50:30.990796-06	5463:5463:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000164	2018-06-06 11:50:41.021548-06	5484:5484:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000165	2018-06-06 11:50:51.027679-06	5505:5505:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000166	2018-06-06 11:51:01.065439-06	5530:5530:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000167	2018-06-06 11:51:11.085966-06	5553:5553:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000168	2018-06-06 11:51:21.129145-06	5577:5577:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000169	2018-06-06 11:51:31.155626-06	5599:5599:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000170	2018-06-06 11:51:41.632108-06	5622:5622:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000171	2018-06-06 11:51:51.670149-06	5645:5645:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000172	2018-06-06 11:52:01.71576-06	5672:5672:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000173	2018-06-06 11:52:11.704221-06	5697:5697:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000174	2018-06-06 11:52:21.740797-06	5723:5723:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000175	2018-06-06 11:52:31.746743-06	5745:5745:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000176	2018-06-06 11:52:41.751339-06	5770:5770:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000177	2018-06-06 11:52:51.754639-06	5792:5792:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000178	2018-06-06 11:53:01.787056-06	5818:5818:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000179	2018-06-06 11:53:11.810894-06	5841:5841:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000180	2018-06-06 11:53:21.851685-06	5872:5872:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000181	2018-06-06 11:53:31.877748-06	5898:5898:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000182	2018-06-06 11:53:41.897448-06	5926:5926:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000183	2018-06-06 11:53:51.92605-06	5952:5952:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000184	2018-06-06 11:54:01.962005-06	5981:5981:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000185	2018-06-06 11:54:11.985602-06	6004:6004:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000186	2018-06-06 11:54:22.009917-06	6034:6034:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000187	2018-06-06 11:54:32.0563-06	6060:6060:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000188	2018-06-06 11:54:42.094134-06	6089:6089:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000189	2018-06-06 11:54:52.15046-06	6114:6114:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000190	2018-06-06 11:55:02.19724-06	6141:6141:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000191	2018-06-06 11:55:12.228095-06	6166:6166:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000176	2018-06-06 11:55:14.554801-06	6174:6174:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000192	2018-06-06 11:55:22.27293-06	6196:6196:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000193	2018-06-06 11:55:32.313202-06	6224:6224:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000177	2018-06-06 11:55:24.597609-06	6203:6203:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000178	2018-06-06 11:55:34.638042-06	6231:6231:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000194	2018-06-06 11:55:42.343111-06	6252:6252:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000195	2018-06-06 11:55:52.362989-06	6278:6278:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000179	2018-06-06 11:55:44.688163-06	6259:6259:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000180	2018-06-06 11:55:54.708015-06	6284:6284:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000196	2018-06-06 11:56:02.385523-06	6304:6304:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
1	5000000197	2018-06-06 11:56:12.43131-06	6329:6329:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
2	5000000181	2018-06-06 11:56:04.74623-06	6311:6311:	SYNC	\N	\N	\N	\N	\N	\N	\N	\N
\.


--
-- Data for Name: sl_event_lock; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_event_lock (dummy) FROM stdin;
\.


--
-- Data for Name: sl_listen; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_listen (li_origin, li_provider, li_receiver) FROM stdin;
1	1	1
2	2	1
2	1	1
1	1	2
\.


--
-- Data for Name: sl_log_1; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_log_1 (log_origin, log_txid, log_tableid, log_actionseq, log_tablenspname, log_tablerelname, log_cmdtype, log_cmdupdncols, log_cmdargs) FROM stdin;
\.


--
-- Data for Name: sl_log_2; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_log_2 (log_origin, log_txid, log_tableid, log_actionseq, log_tablenspname, log_tablerelname, log_cmdtype, log_cmdupdncols, log_cmdargs) FROM stdin;
\.


--
-- Data for Name: sl_log_script; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_log_script (log_origin, log_txid, log_actionseq, log_cmdtype, log_cmdargs) FROM stdin;
\.


--
-- Data for Name: sl_node; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_node (no_id, no_active, no_comment, no_failed) FROM stdin;
1	t	Nodo maestro	f
2	t	Nodo Esclavo	f
\.


--
-- Data for Name: sl_nodelock; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_nodelock (nl_nodeid, nl_conncnt, nl_backendpid) FROM stdin;
1	0	14312
\.


--
-- Data for Name: sl_path; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_path (pa_server, pa_client, pa_conninfo, pa_connretry) FROM stdin;
1	1	dbname = launica port = 5030 host =localhost user = postgres password=clickbalance123	10
2	1	dbname = postgres port = 5030 host =localhost user = postgres password=clickbalance123	10
1	2	<event pending>	10
\.


--
-- Data for Name: sl_registry; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_registry (reg_key, reg_int4, reg_text, reg_timestamp) FROM stdin;
logswitch.laststart	\N	\N	2018-06-06 11:55:24.378879-06
\.


--
-- Data for Name: sl_seqlog; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_seqlog (seql_seqid, seql_origin, seql_ev_seqno, seql_last_value) FROM stdin;
\.


--
-- Data for Name: sl_sequence; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_sequence (seq_id, seq_reloid, seq_relname, seq_nspname, seq_set, seq_comment) FROM stdin;
\.


--
-- Data for Name: sl_set; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_set (set_id, set_origin, set_locked, set_comment) FROM stdin;
1	1	\N	tablas de conjunto
\.


--
-- Data for Name: sl_setsync; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_setsync (ssy_setid, ssy_origin, ssy_seqno, ssy_snapshot, ssy_action_list) FROM stdin;
\.


--
-- Data for Name: sl_subscribe; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_subscribe (sub_set, sub_provider, sub_receiver, sub_forward, sub_active) FROM stdin;
1	1	2	f	t
\.


--
-- Data for Name: sl_table; Type: TABLE DATA; Schema: _primer_cluster2; Owner: postgres
--

COPY _primer_cluster2.sl_table (tab_id, tab_reloid, tab_relname, tab_nspname, tab_set, tab_idxname, tab_altered, tab_comment) FROM stdin;
1	17021	agente	comercial	1	pk_agente	f	clientes
2	17037	clientes	cxc	1	pk_clientes	f	agentes
\.


--
-- Data for Name: agente; Type: TABLE DATA; Schema: comercial; Owner: postgres
--

COPY comercial.agente (id, apellido_paterno, apellido_materno, nombre, rfc, zona_id) FROM stdin;
4	piña	borrego	anel	1234567891011	2
3	lopez	malacon	miguel	loem971123hsl	2
2	mejia	salcido	maria	MEFS940226HSL	5
6	lopez	malacon	jesus	LOMJ020831HSL	1
\.


--
-- Data for Name: comisiones; Type: TABLE DATA; Schema: comercial; Owner: postgres
--

COPY comercial.comisiones (id, venta_id, agente_id, total, comisionescol) FROM stdin;
\.


--
-- Data for Name: detalleventa; Type: TABLE DATA; Schema: comercial; Owner: postgres
--

COPY comercial.detalleventa (id, detalle_venta_id, producto_id, cantidad, precio, tasa_iva_id) FROM stdin;
\.


--
-- Data for Name: venta; Type: TABLE DATA; Schema: comercial; Owner: postgres
--

COPY comercial.venta (id, folio, fecha, cliente_id, agente_id, estatus) FROM stdin;
\.


--
-- Data for Name: clientes; Type: TABLE DATA; Schema: cxc; Owner: postgres
--

COPY cxc.clientes (id, nombre, apellido_paterno, apellido_materno, rfc, agente_id) FROM stdin;
\.


--
-- Data for Name: clientes_impar; Type: TABLE DATA; Schema: cxc; Owner: postgres
--

COPY cxc.clientes_impar (id, nombre, apellido_paterno, apellido_materno, rfc, agente_id) FROM stdin;
3	jose	lopez	malacon	lomm960619hsl	2
\.


--
-- Data for Name: clientes_par; Type: TABLE DATA; Schema: cxc; Owner: postgres
--

COPY cxc.clientes_par (id, nombre, apellido_paterno, apellido_materno, rfc, agente_id) FROM stdin;
\.


--
-- Data for Name: cuentasporcobrar; Type: TABLE DATA; Schema: cxc; Owner: postgres
--

COPY cxc.cuentasporcobrar (id, folio, cliente_id, venta_id, total, saldo) FROM stdin;
\.


--
-- Data for Name: movimientoscxc; Type: TABLE DATA; Schema: cxc; Owner: postgres
--

COPY cxc.movimientoscxc (id, tipo_movimiento_id, folio, fecha, importe, naturaleza, cxc_id) FROM stdin;
\.


--
-- Data for Name: tipomovimientocxc; Type: TABLE DATA; Schema: cxc; Owner: postgres
--

COPY cxc.tipomovimientocxc (id, nombre, naturaleza) FROM stdin;
\.


--
-- Data for Name: movimientoinventario; Type: TABLE DATA; Schema: inventarios; Owner: postgres
--

COPY inventarios.movimientoinventario (id, folio, producto_id, fecha, cantidad, naturaleza, tipo_movimiento_id, movimientoinventariocol, almacen_id, movimientoinventariocol1) FROM stdin;
\.


--
-- Data for Name: producto; Type: TABLE DATA; Schema: inventarios; Owner: postgres
--

COPY inventarios.producto (id, nombre) FROM stdin;
\.


--
-- Data for Name: tipomovimiento; Type: TABLE DATA; Schema: inventarios; Owner: postgres
--

COPY inventarios.tipomovimiento (id, nombre, naturaleza) FROM stdin;
\.


--
-- Name: sl_action_seq; Type: SEQUENCE SET; Schema: _primer_cluster2; Owner: postgres
--

SELECT pg_catalog.setval('_primer_cluster2.sl_action_seq', 1, false);


--
-- Name: sl_event_seq; Type: SEQUENCE SET; Schema: _primer_cluster2; Owner: postgres
--

SELECT pg_catalog.setval('_primer_cluster2.sl_event_seq', 5000000257, true);


--
-- Name: sl_local_node_id; Type: SEQUENCE SET; Schema: _primer_cluster2; Owner: postgres
--

SELECT pg_catalog.setval('_primer_cluster2.sl_local_node_id', 1, true);


--
-- Name: sl_log_status; Type: SEQUENCE SET; Schema: _primer_cluster2; Owner: postgres
--

SELECT pg_catalog.setval('_primer_cluster2.sl_log_status', 0, true);


--
-- Name: sl_nodelock_nl_conncnt_seq; Type: SEQUENCE SET; Schema: _primer_cluster2; Owner: postgres
--

SELECT pg_catalog.setval('_primer_cluster2.sl_nodelock_nl_conncnt_seq', 1, false);


--
-- Name: agente_id_seq; Type: SEQUENCE SET; Schema: comercial; Owner: postgres
--

SELECT pg_catalog.setval('comercial.agente_id_seq', 6, true);


--
-- Name: comisiones_id_seq; Type: SEQUENCE SET; Schema: comercial; Owner: postgres
--

SELECT pg_catalog.setval('comercial.comisiones_id_seq', 1, false);


--
-- Name: detalleventa_id_seq; Type: SEQUENCE SET; Schema: comercial; Owner: postgres
--

SELECT pg_catalog.setval('comercial.detalleventa_id_seq', 1, false);


--
-- Name: venta_id_seq; Type: SEQUENCE SET; Schema: comercial; Owner: postgres
--

SELECT pg_catalog.setval('comercial.venta_id_seq', 1, false);


--
-- Name: clientes_id_seq; Type: SEQUENCE SET; Schema: cxc; Owner: postgres
--

SELECT pg_catalog.setval('cxc.clientes_id_seq', 3, true);


--
-- Name: cuentasporcobrar_id_seq; Type: SEQUENCE SET; Schema: cxc; Owner: postgres
--

SELECT pg_catalog.setval('cxc.cuentasporcobrar_id_seq', 1, false);


--
-- Name: movimientoscxc_id_seq; Type: SEQUENCE SET; Schema: cxc; Owner: postgres
--

SELECT pg_catalog.setval('cxc.movimientoscxc_id_seq', 1, false);


--
-- Name: tipomovimientocxc_id_seq; Type: SEQUENCE SET; Schema: cxc; Owner: postgres
--

SELECT pg_catalog.setval('cxc.tipomovimientocxc_id_seq', 1, false);


--
-- Name: movimientoinventario_id_seq; Type: SEQUENCE SET; Schema: inventarios; Owner: postgres
--

SELECT pg_catalog.setval('inventarios.movimientoinventario_id_seq', 1, false);


--
-- Name: producto_id_seq; Type: SEQUENCE SET; Schema: inventarios; Owner: postgres
--

SELECT pg_catalog.setval('inventarios.producto_id_seq', 1, false);


--
-- Name: sl_components sl_components_pkey; Type: CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_components
    ADD CONSTRAINT sl_components_pkey PRIMARY KEY (co_actor);


--
-- Name: sl_event sl_event-pkey; Type: CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_event
    ADD CONSTRAINT "sl_event-pkey" PRIMARY KEY (ev_origin, ev_seqno);


--
-- Name: sl_listen sl_listen-pkey; Type: CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_listen
    ADD CONSTRAINT "sl_listen-pkey" PRIMARY KEY (li_origin, li_provider, li_receiver);


--
-- Name: sl_node sl_node-pkey; Type: CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_node
    ADD CONSTRAINT "sl_node-pkey" PRIMARY KEY (no_id);


--
-- Name: sl_nodelock sl_nodelock-pkey; Type: CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_nodelock
    ADD CONSTRAINT "sl_nodelock-pkey" PRIMARY KEY (nl_nodeid, nl_conncnt);


--
-- Name: sl_path sl_path-pkey; Type: CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_path
    ADD CONSTRAINT "sl_path-pkey" PRIMARY KEY (pa_server, pa_client);


--
-- Name: sl_registry sl_registry_pkey; Type: CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_registry
    ADD CONSTRAINT sl_registry_pkey PRIMARY KEY (reg_key);


--
-- Name: sl_sequence sl_sequence-pkey; Type: CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_sequence
    ADD CONSTRAINT "sl_sequence-pkey" PRIMARY KEY (seq_id);


--
-- Name: sl_sequence sl_sequence_seq_reloid_key; Type: CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_sequence
    ADD CONSTRAINT sl_sequence_seq_reloid_key UNIQUE (seq_reloid);


--
-- Name: sl_set sl_set-pkey; Type: CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_set
    ADD CONSTRAINT "sl_set-pkey" PRIMARY KEY (set_id);


--
-- Name: sl_setsync sl_setsync-pkey; Type: CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_setsync
    ADD CONSTRAINT "sl_setsync-pkey" PRIMARY KEY (ssy_setid);


--
-- Name: sl_subscribe sl_subscribe-pkey; Type: CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_subscribe
    ADD CONSTRAINT "sl_subscribe-pkey" PRIMARY KEY (sub_receiver, sub_set);


--
-- Name: sl_table sl_table-pkey; Type: CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_table
    ADD CONSTRAINT "sl_table-pkey" PRIMARY KEY (tab_id);


--
-- Name: sl_table sl_table_tab_reloid_key; Type: CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_table
    ADD CONSTRAINT sl_table_tab_reloid_key UNIQUE (tab_reloid);


--
-- Name: agente pk_agente; Type: CONSTRAINT; Schema: comercial; Owner: postgres
--

ALTER TABLE ONLY comercial.agente
    ADD CONSTRAINT pk_agente PRIMARY KEY (id);


--
-- Name: comisiones pk_comisiones; Type: CONSTRAINT; Schema: comercial; Owner: postgres
--

ALTER TABLE ONLY comercial.comisiones
    ADD CONSTRAINT pk_comisiones PRIMARY KEY (id);


--
-- Name: detalleventa pk_detalleventa; Type: CONSTRAINT; Schema: comercial; Owner: postgres
--

ALTER TABLE ONLY comercial.detalleventa
    ADD CONSTRAINT pk_detalleventa PRIMARY KEY (id);


--
-- Name: venta pk_venta; Type: CONSTRAINT; Schema: comercial; Owner: postgres
--

ALTER TABLE ONLY comercial.venta
    ADD CONSTRAINT pk_venta PRIMARY KEY (id);


--
-- Name: clientes pk_clientes; Type: CONSTRAINT; Schema: cxc; Owner: postgres
--

ALTER TABLE ONLY cxc.clientes
    ADD CONSTRAINT pk_clientes PRIMARY KEY (id);


--
-- Name: cuentasporcobrar pk_cxc; Type: CONSTRAINT; Schema: cxc; Owner: postgres
--

ALTER TABLE ONLY cxc.cuentasporcobrar
    ADD CONSTRAINT pk_cxc PRIMARY KEY (id);


--
-- Name: movimientoscxc pk_movcxc; Type: CONSTRAINT; Schema: cxc; Owner: postgres
--

ALTER TABLE ONLY cxc.movimientoscxc
    ADD CONSTRAINT pk_movcxc PRIMARY KEY (id);


--
-- Name: tipomovimientocxc pk_tipmov; Type: CONSTRAINT; Schema: cxc; Owner: postgres
--

ALTER TABLE ONLY cxc.tipomovimientocxc
    ADD CONSTRAINT pk_tipmov PRIMARY KEY (id);


--
-- Name: movimientoinventario pk_movimientosinv; Type: CONSTRAINT; Schema: inventarios; Owner: postgres
--

ALTER TABLE ONLY inventarios.movimientoinventario
    ADD CONSTRAINT pk_movimientosinv PRIMARY KEY (id);


--
-- Name: producto pk_producto; Type: CONSTRAINT; Schema: inventarios; Owner: postgres
--

ALTER TABLE ONLY inventarios.producto
    ADD CONSTRAINT pk_producto PRIMARY KEY (id);


--
-- Name: tipomovimiento pk_tipmov; Type: CONSTRAINT; Schema: inventarios; Owner: postgres
--

ALTER TABLE ONLY inventarios.tipomovimiento
    ADD CONSTRAINT pk_tipmov PRIMARY KEY (id);


--
-- Name: PartInd_primer_cluster2_sl_log_1-node-1; Type: INDEX; Schema: _primer_cluster2; Owner: postgres
--

CREATE INDEX "PartInd_primer_cluster2_sl_log_1-node-1" ON _primer_cluster2.sl_log_1 USING btree (log_txid) WHERE (log_origin = 1);


--
-- Name: PartInd_primer_cluster2_sl_log_2-node-1; Type: INDEX; Schema: _primer_cluster2; Owner: postgres
--

CREATE INDEX "PartInd_primer_cluster2_sl_log_2-node-1" ON _primer_cluster2.sl_log_2 USING btree (log_txid) WHERE (log_origin = 1);


--
-- Name: sl_apply_stats_idx1; Type: INDEX; Schema: _primer_cluster2; Owner: postgres
--

CREATE INDEX sl_apply_stats_idx1 ON _primer_cluster2.sl_apply_stats USING btree (as_origin);


--
-- Name: sl_confirm_idx1; Type: INDEX; Schema: _primer_cluster2; Owner: postgres
--

CREATE INDEX sl_confirm_idx1 ON _primer_cluster2.sl_confirm USING btree (con_origin, con_received, con_seqno);


--
-- Name: sl_confirm_idx2; Type: INDEX; Schema: _primer_cluster2; Owner: postgres
--

CREATE INDEX sl_confirm_idx2 ON _primer_cluster2.sl_confirm USING btree (con_received, con_seqno);


--
-- Name: sl_log_1_idx1; Type: INDEX; Schema: _primer_cluster2; Owner: postgres
--

CREATE INDEX sl_log_1_idx1 ON _primer_cluster2.sl_log_1 USING btree (log_origin, log_txid, log_actionseq);


--
-- Name: sl_log_2_idx1; Type: INDEX; Schema: _primer_cluster2; Owner: postgres
--

CREATE INDEX sl_log_2_idx1 ON _primer_cluster2.sl_log_2 USING btree (log_origin, log_txid, log_actionseq);


--
-- Name: sl_log_script_idx1; Type: INDEX; Schema: _primer_cluster2; Owner: postgres
--

CREATE INDEX sl_log_script_idx1 ON _primer_cluster2.sl_log_script USING btree (log_origin, log_txid, log_actionseq);


--
-- Name: sl_seqlog_idx; Type: INDEX; Schema: _primer_cluster2; Owner: postgres
--

CREATE INDEX sl_seqlog_idx ON _primer_cluster2.sl_seqlog USING btree (seql_origin, seql_ev_seqno, seql_seqid);


--
-- Name: sl_log_1 apply_trigger; Type: TRIGGER; Schema: _primer_cluster2; Owner: postgres
--

CREATE TRIGGER apply_trigger BEFORE INSERT ON _primer_cluster2.sl_log_1 FOR EACH ROW EXECUTE PROCEDURE _primer_cluster2.logapply('_primer_cluster2');

ALTER TABLE _primer_cluster2.sl_log_1 ENABLE REPLICA TRIGGER apply_trigger;


--
-- Name: sl_log_2 apply_trigger; Type: TRIGGER; Schema: _primer_cluster2; Owner: postgres
--

CREATE TRIGGER apply_trigger BEFORE INSERT ON _primer_cluster2.sl_log_2 FOR EACH ROW EXECUTE PROCEDURE _primer_cluster2.logapply('_primer_cluster2');

ALTER TABLE _primer_cluster2.sl_log_2 ENABLE REPLICA TRIGGER apply_trigger;


--
-- Name: agente _primer_cluster2_denyaccess; Type: TRIGGER; Schema: comercial; Owner: postgres
--

CREATE TRIGGER _primer_cluster2_denyaccess BEFORE INSERT OR DELETE OR UPDATE ON comercial.agente FOR EACH ROW EXECUTE PROCEDURE _primer_cluster2.denyaccess('_primer_cluster2');

ALTER TABLE comercial.agente DISABLE TRIGGER _primer_cluster2_denyaccess;


--
-- Name: agente _primer_cluster2_logtrigger; Type: TRIGGER; Schema: comercial; Owner: postgres
--

CREATE TRIGGER _primer_cluster2_logtrigger AFTER INSERT OR DELETE OR UPDATE ON comercial.agente FOR EACH ROW EXECUTE PROCEDURE _primer_cluster2.logtrigger('_primer_cluster2', '1', 'k');


--
-- Name: agente _primer_cluster2_truncatedeny; Type: TRIGGER; Schema: comercial; Owner: postgres
--

CREATE TRIGGER _primer_cluster2_truncatedeny BEFORE TRUNCATE ON comercial.agente FOR EACH STATEMENT EXECUTE PROCEDURE _primer_cluster2.deny_truncate();

ALTER TABLE comercial.agente DISABLE TRIGGER _primer_cluster2_truncatedeny;


--
-- Name: agente _primer_cluster2_truncatetrigger; Type: TRIGGER; Schema: comercial; Owner: postgres
--

CREATE TRIGGER _primer_cluster2_truncatetrigger BEFORE TRUNCATE ON comercial.agente FOR EACH STATEMENT EXECUTE PROCEDURE _primer_cluster2.log_truncate('1');


--
-- Name: clientes _primer_cluster2_denyaccess; Type: TRIGGER; Schema: cxc; Owner: postgres
--

CREATE TRIGGER _primer_cluster2_denyaccess BEFORE INSERT OR DELETE OR UPDATE ON cxc.clientes FOR EACH ROW EXECUTE PROCEDURE _primer_cluster2.denyaccess('_primer_cluster2');

ALTER TABLE cxc.clientes DISABLE TRIGGER _primer_cluster2_denyaccess;


--
-- Name: clientes _primer_cluster2_logtrigger; Type: TRIGGER; Schema: cxc; Owner: postgres
--

CREATE TRIGGER _primer_cluster2_logtrigger AFTER INSERT OR DELETE OR UPDATE ON cxc.clientes FOR EACH ROW EXECUTE PROCEDURE _primer_cluster2.logtrigger('_primer_cluster2', '2', 'k');


--
-- Name: clientes _primer_cluster2_truncatedeny; Type: TRIGGER; Schema: cxc; Owner: postgres
--

CREATE TRIGGER _primer_cluster2_truncatedeny BEFORE TRUNCATE ON cxc.clientes FOR EACH STATEMENT EXECUTE PROCEDURE _primer_cluster2.deny_truncate();

ALTER TABLE cxc.clientes DISABLE TRIGGER _primer_cluster2_truncatedeny;


--
-- Name: clientes _primer_cluster2_truncatetrigger; Type: TRIGGER; Schema: cxc; Owner: postgres
--

CREATE TRIGGER _primer_cluster2_truncatetrigger BEFORE TRUNCATE ON cxc.clientes FOR EACH STATEMENT EXECUTE PROCEDURE _primer_cluster2.log_truncate('2');


--
-- Name: clientes insert_clientes_trigger; Type: TRIGGER; Schema: cxc; Owner: postgres
--

CREATE TRIGGER insert_clientes_trigger BEFORE INSERT ON cxc.clientes FOR EACH ROW EXECUTE PROCEDURE cxc.clientes_id_insert();


--
-- Name: sl_listen li_origin-no_id-ref; Type: FK CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_listen
    ADD CONSTRAINT "li_origin-no_id-ref" FOREIGN KEY (li_origin) REFERENCES _primer_cluster2.sl_node(no_id);


--
-- Name: sl_path pa_client-no_id-ref; Type: FK CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_path
    ADD CONSTRAINT "pa_client-no_id-ref" FOREIGN KEY (pa_client) REFERENCES _primer_cluster2.sl_node(no_id);


--
-- Name: sl_path pa_server-no_id-ref; Type: FK CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_path
    ADD CONSTRAINT "pa_server-no_id-ref" FOREIGN KEY (pa_server) REFERENCES _primer_cluster2.sl_node(no_id);


--
-- Name: sl_sequence seq_set-set_id-ref; Type: FK CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_sequence
    ADD CONSTRAINT "seq_set-set_id-ref" FOREIGN KEY (seq_set) REFERENCES _primer_cluster2.sl_set(set_id);


--
-- Name: sl_set set_origin-no_id-ref; Type: FK CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_set
    ADD CONSTRAINT "set_origin-no_id-ref" FOREIGN KEY (set_origin) REFERENCES _primer_cluster2.sl_node(no_id);


--
-- Name: sl_listen sl_listen-sl_path-ref; Type: FK CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_listen
    ADD CONSTRAINT "sl_listen-sl_path-ref" FOREIGN KEY (li_provider, li_receiver) REFERENCES _primer_cluster2.sl_path(pa_server, pa_client);


--
-- Name: sl_subscribe sl_subscribe-sl_path-ref; Type: FK CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_subscribe
    ADD CONSTRAINT "sl_subscribe-sl_path-ref" FOREIGN KEY (sub_provider, sub_receiver) REFERENCES _primer_cluster2.sl_path(pa_server, pa_client);


--
-- Name: sl_setsync ssy_origin-no_id-ref; Type: FK CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_setsync
    ADD CONSTRAINT "ssy_origin-no_id-ref" FOREIGN KEY (ssy_origin) REFERENCES _primer_cluster2.sl_node(no_id);


--
-- Name: sl_setsync ssy_setid-set_id-ref; Type: FK CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_setsync
    ADD CONSTRAINT "ssy_setid-set_id-ref" FOREIGN KEY (ssy_setid) REFERENCES _primer_cluster2.sl_set(set_id);


--
-- Name: sl_subscribe sub_set-set_id-ref; Type: FK CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_subscribe
    ADD CONSTRAINT "sub_set-set_id-ref" FOREIGN KEY (sub_set) REFERENCES _primer_cluster2.sl_set(set_id);


--
-- Name: sl_table tab_set-set_id-ref; Type: FK CONSTRAINT; Schema: _primer_cluster2; Owner: postgres
--

ALTER TABLE ONLY _primer_cluster2.sl_table
    ADD CONSTRAINT "tab_set-set_id-ref" FOREIGN KEY (tab_set) REFERENCES _primer_cluster2.sl_set(set_id);


--
-- Name: comisiones comisiones_agente_id_fkey; Type: FK CONSTRAINT; Schema: comercial; Owner: postgres
--

ALTER TABLE ONLY comercial.comisiones
    ADD CONSTRAINT comisiones_agente_id_fkey FOREIGN KEY (agente_id) REFERENCES comercial.agente(id);


--
-- Name: comisiones comisiones_venta_id_fkey; Type: FK CONSTRAINT; Schema: comercial; Owner: postgres
--

ALTER TABLE ONLY comercial.comisiones
    ADD CONSTRAINT comisiones_venta_id_fkey FOREIGN KEY (venta_id) REFERENCES comercial.venta(id);


--
-- Name: detalleventa detalleventa_detalle_venta_id_fkey; Type: FK CONSTRAINT; Schema: comercial; Owner: postgres
--

ALTER TABLE ONLY comercial.detalleventa
    ADD CONSTRAINT detalleventa_detalle_venta_id_fkey FOREIGN KEY (detalle_venta_id) REFERENCES comercial.venta(id);


--
-- Name: detalleventa detalleventa_producto_id_fkey; Type: FK CONSTRAINT; Schema: comercial; Owner: postgres
--

ALTER TABLE ONLY comercial.detalleventa
    ADD CONSTRAINT detalleventa_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES inventarios.producto(id);


--
-- Name: venta venta_agente_id_fkey; Type: FK CONSTRAINT; Schema: comercial; Owner: postgres
--

ALTER TABLE ONLY comercial.venta
    ADD CONSTRAINT venta_agente_id_fkey FOREIGN KEY (agente_id) REFERENCES comercial.agente(id);


--
-- Name: venta venta_cliente_id_fkey; Type: FK CONSTRAINT; Schema: comercial; Owner: postgres
--

ALTER TABLE ONLY comercial.venta
    ADD CONSTRAINT venta_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES cxc.clientes(id);


--
-- Name: clientes clientes_agente_id_fkey; Type: FK CONSTRAINT; Schema: cxc; Owner: postgres
--

ALTER TABLE ONLY cxc.clientes
    ADD CONSTRAINT clientes_agente_id_fkey FOREIGN KEY (agente_id) REFERENCES comercial.agente(id);


--
-- Name: cuentasporcobrar cuentasporcobrar_cliente_id_fkey; Type: FK CONSTRAINT; Schema: cxc; Owner: postgres
--

ALTER TABLE ONLY cxc.cuentasporcobrar
    ADD CONSTRAINT cuentasporcobrar_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES cxc.clientes(id);


--
-- Name: cuentasporcobrar cuentasporcobrar_venta_id_fkey; Type: FK CONSTRAINT; Schema: cxc; Owner: postgres
--

ALTER TABLE ONLY cxc.cuentasporcobrar
    ADD CONSTRAINT cuentasporcobrar_venta_id_fkey FOREIGN KEY (venta_id) REFERENCES comercial.venta(id);


--
-- Name: movimientoscxc movimientoscxc_cxc_id_fkey; Type: FK CONSTRAINT; Schema: cxc; Owner: postgres
--

ALTER TABLE ONLY cxc.movimientoscxc
    ADD CONSTRAINT movimientoscxc_cxc_id_fkey FOREIGN KEY (cxc_id) REFERENCES cxc.cuentasporcobrar(id);


--
-- Name: movimientoscxc movimientoscxc_tipo_movimiento_id_fkey; Type: FK CONSTRAINT; Schema: cxc; Owner: postgres
--

ALTER TABLE ONLY cxc.movimientoscxc
    ADD CONSTRAINT movimientoscxc_tipo_movimiento_id_fkey FOREIGN KEY (tipo_movimiento_id) REFERENCES cxc.tipomovimientocxc(id);


--
-- Name: movimientoinventario movimientoinventario_producto_id_fkey; Type: FK CONSTRAINT; Schema: inventarios; Owner: postgres
--

ALTER TABLE ONLY inventarios.movimientoinventario
    ADD CONSTRAINT movimientoinventario_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES inventarios.producto(id);


--
-- Name: movimientoinventario movimientoinventario_tipo_movimiento_id_fkey; Type: FK CONSTRAINT; Schema: inventarios; Owner: postgres
--

ALTER TABLE ONLY inventarios.movimientoinventario
    ADD CONSTRAINT movimientoinventario_tipo_movimiento_id_fkey FOREIGN KEY (tipo_movimiento_id) REFERENCES inventarios.tipomovimiento(id);


--
-- Name: SCHEMA _primer_cluster2; Type: ACL; Schema: -; Owner: postgres
--

GRANT USAGE ON SCHEMA _primer_cluster2 TO PUBLIC;


--
-- PostgreSQL database dump complete
--

