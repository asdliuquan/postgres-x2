--
-- PREPARED TRANSACTIONS (two-phase commit)
--
-- We can't readily test persistence of prepared xacts within the
-- regression script framework, unfortunately.  Note that a crash
-- isn't really needed ... stopping and starting the postmaster would
-- be enough, but we can't even do that here.


-- create a simple table that we'll use in the tests
CREATE TABLE pxtest1 (foobar VARCHAR(10)) distribute by replication;

INSERT INTO pxtest1 VALUES ('aaa');


-- Test PREPARE TRANSACTION
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
UPDATE pxtest1 SET foobar = 'bbb' WHERE foobar = 'aaa';
SELECT * FROM pxtest1 ORDER BY foobar;
PREPARE TRANSACTION 'foo1';

SELECT * FROM pxtest1 ORDER BY foobar;

-- Test pg_prepared_xacts system view
SELECT gid FROM pg_prepared_xacts ORDER BY gid;
-- Test pgxc_prepared_xacts system view
SELECT pgxc_prepared_xact FROM pgxc_prepared_xacts ORDER by 1;

-- Test ROLLBACK PREPARED
ROLLBACK PREPARED 'foo1';

SELECT * FROM pxtest1  ORDER BY foobar;

-- Check prepared transactions on Coordinator
SELECT gid FROM pg_prepared_xacts ORDER BY gid;
-- Check prepared transactions in the cluster
SELECT pgxc_prepared_xact FROM pgxc_prepared_xacts ORDER by 1;

-- Test COMMIT PREPARED
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
INSERT INTO pxtest1 VALUES ('ddd');
SELECT * FROM pxtest1 ORDER BY foobar;
PREPARE TRANSACTION 'foo2';

SELECT * FROM pxtest1  ORDER BY foobar;

COMMIT PREPARED 'foo2';

SELECT * FROM pxtest1  ORDER BY foobar;

-- Test duplicate gids
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
UPDATE pxtest1 SET foobar = 'eee' WHERE foobar = 'ddd';
SELECT * FROM pxtest1  ORDER BY foobar;
PREPARE TRANSACTION 'foo3';

-- Check prepared transactions on Coordinator
SELECT gid FROM pg_prepared_xacts ORDER BY gid;
-- Check prepared transactions in the cluster
SELECT pgxc_prepared_xact FROM pgxc_prepared_xacts ORDER by 1;

BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
INSERT INTO pxtest1 VALUES ('fff');

-- This should fail, because the gid foo3 is already in use
PREPARE TRANSACTION 'foo3';

SELECT * FROM pxtest1  ORDER BY foobar;

ROLLBACK PREPARED 'foo3';

SELECT * FROM pxtest1  ORDER BY foobar;

-- Test serialization failure (SSI)
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
UPDATE pxtest1 SET foobar = 'eee' WHERE foobar = 'ddd';
SELECT * FROM pxtest1;
PREPARE TRANSACTION 'foo4';

SELECT gid FROM pg_prepared_xacts;

BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SELECT * FROM pxtest1;

-- This should fail, because the two transactions have a write-skew anomaly
INSERT INTO pxtest1 VALUES ('fff');
PREPARE TRANSACTION 'foo5';

SELECT gid FROM pg_prepared_xacts;

ROLLBACK PREPARED 'foo4';

SELECT gid FROM pg_prepared_xacts;

-- In Postgres-XC, serializable is not yet supported, and SERIALIZABLE falls to
-- read-committed silently, so rollback transaction properly
ROLLBACK PREPARED 'foo5';

-- Clean up
DROP TABLE pxtest1;

-- Test subtransactions
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
  CREATE TABLE pxtest2 (a int);
  INSERT INTO pxtest2 VALUES (1);
  SAVEPOINT a;
    INSERT INTO pxtest2 VALUES (2);
  ROLLBACK TO a;
  SAVEPOINT b;
  INSERT INTO pxtest2 VALUES (3);
PREPARE TRANSACTION 'regress-one';

CREATE TABLE pxtest3(fff int);

-- Test shared invalidation
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
  DROP TABLE pxtest3;
  CREATE TABLE pxtest4 (a int);
  INSERT INTO pxtest4 VALUES (1);
  INSERT INTO pxtest4 VALUES (2);
  DECLARE foo CURSOR FOR SELECT * FROM pxtest4;
  -- Fetch 1 tuple, keeping the cursor open
  FETCH 1 FROM foo;
PREPARE TRANSACTION 'regress-two';

-- No such cursor
FETCH 1 FROM foo;

-- Table doesn't exist, the creation hasn't been committed yet
SELECT * FROM pxtest2;

-- There should be two prepared transactions
SELECT gid FROM pg_prepared_xacts ORDER BY gid;
-- Check prepared transactions in the cluster
SELECT pgxc_prepared_xact FROM pgxc_prepared_xacts ORDER by 1;

-- pxtest3 should be locked because of the pending DROP
set statement_timeout to 2000;
SELECT * FROM pxtest3;
reset statement_timeout;

-- Disconnect, we will continue testing in a different backend
\c -

-- There should still be two prepared transactions
SELECT gid FROM pg_prepared_xacts ORDER BY gid;
-- Check prepared transactions in the cluster
SELECT pgxc_prepared_xact FROM pgxc_prepared_xacts ORDER by 1;

-- pxtest3 should still be locked because of the pending DROP
set statement_timeout to 2000;
SELECT * FROM pxtest3;
reset statement_timeout;

-- Commit table creation
COMMIT PREPARED 'regress-one';
\d pxtest2
SELECT * FROM pxtest2;

-- There should be one prepared transaction
SELECT gid FROM pg_prepared_xacts ORDER BY 1;
-- Check prepared transactions in the cluster
SELECT pgxc_prepared_xact FROM pgxc_prepared_xacts ORDER by 1;

-- Commit table drop
COMMIT PREPARED 'regress-two';
SELECT * FROM pxtest3;

-- There should be no prepared transactions
SELECT gid FROM pg_prepared_xacts ORDER BY gid;
-- Check prepared transactions in the cluster
SELECT pgxc_prepared_xact FROM pgxc_prepared_xacts ORDER by 1;

-- Clean up
DROP TABLE pxtest2;
DROP TABLE pxtest3;  -- will still be there if prepared xacts are disabled
DROP TABLE pxtest4;
