-- SETUP
CREATE OR REPLACE FUNCTION do_explain(stmt text) RETURNS table(a text) AS
$_$
DECLARE
    ret text;
BEGIN
    FOR ret IN EXECUTE format('EXPLAIN (FORMAT text) %s', stmt) LOOP
        a := ret;
        RETURN next ;
    END LOOP;
END;
$_$
LANGUAGE plpgsql;

CREATE EXTENSION hypopg;

CREATE TABLE hypo (id integer, val text);

INSERT INTO hypo SELECT i, 'line ' || i
FROM generate_series(1,100000) f(i);

ANALYZE hypo;

-- TESTS
SELECT COUNT(*) AS nb
FROM public.hypopg_create_index('SELECT 1;CREATE INDEX ON hypo(id); SELECT 2');

SELECT nspname, relname, amname FROM public.hypopg_list_indexes();

-- Should use hypothetical index
SELECT COUNT(*) FROM do_explain('SELECT * FROM hypo WHERE id = 1') e
WHERE e ~ 'Index.*<\d+>btree_hypo.*';

-- Should use hypothetical index
SELECT COUNT(*) FROM do_explain('SELECT * FROM hypo ORDER BY id') e
WHERE e ~ 'Index.*<\d+>btree_hypo.*';

-- Should not use hypothetical index
SELECT COUNT(*) FROM do_explain('SELECT * FROM hypo') e
WHERE e ~ 'Index.*<\d+>btree_hypo.*';

-- Add predicate index
SELECT COUNT(*) AS nb
FROM public.hypopg_create_index('CREATE INDEX ON hypo(id) WHERE id < 5');

-- This specific index should be used
WITH ind AS (
    SELECT indexrelid, row_number() OVER (ORDER BY indexrelid) AS num
    FROM public.hypopg()
),
regexp AS (
    SELECT regexp_replace(e, '.*<(\d+)>.*', E'\\1', 'g') AS r
    FROM do_explain('SELECT * FROM hypo WHERE id < 3') AS e
)

SELECT num
FROM ind
JOIN regexp ON ind.indexrelid::text = regexp.r;

-- Specify fillfactor
SELECT COUNT(*) AS NB
FROM public.hypopg_create_index('CREATE INDEX ON hypo(id) WITH (fillfactor = 10)');

-- Specify an incorrect fillfactor
SELECT COUNT(*) AS NB
FROM public.hypopg_create_index('CREATE INDEX ON hypo(id) WITH (fillfactor = 1)');

-- Index size estimation
SELECT pg_size_pretty(hypopg_relation_size(indexrelid))
FROM hypopg()
ORDER BY indexrelid;

-- locally disable hypoopg
SET hypopg.enabled to false;

-- no hypothetical index should be used
SELECT COUNT(*) FROM do_explain('SELECT * FROM hypo WHERE id = 1') e
WHERE e ~ 'Index.*<\d+>btree_hypo.*';

-- locally re-enable hypoopg
SET hypopg.enabled to true;

-- hypothetical index should be used
SELECT COUNT(*) FROM do_explain('SELECT * FROM hypo WHERE id = 1') e
WHERE e ~ 'Index.*<\d+>btree_hypo.*';

-- Remove one hypothetical index
SELECT hypopg_drop_index(indexrelid) FROM hypopg() ORDER BY indexrelid LIMIT 1;

-- Remove all the hypothetical indexes
SELECT hypopg_reset();

-- index on expression
SELECT COUNT(*) AS NB
FROM public.hypopg_create_index('CREATE INDEX ON hypo (md5(val))');

-- Should use hypothetical index
SELECT COUNT(*) FROM do_explain('SELECT * FROM hypo WHERE md5(val) = md5(''line 1'')') e
WHERE e ~ 'Index.*<\d+>btree_hypo.*';
