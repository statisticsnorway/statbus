-- Test file for SET LOCAL ROLE behavior
-- Demonstrates interaction between transactions, savepoints, DO blocks, and SET LOCAL ROLE.
-- Assumes test users from 60_auth.sql exist.

\echo BEGIN: Demonstration of interaction between transaction and roles in the code

\echo Using a transaction block
SELECT current_user; -- postgres
BEGIN;
  \echo Default current_user is postgres
  SELECT current_user; -- postgres
  \echo Switching to test.admin@example.com
  SET LOCAL ROLE "test.admin@example.com";
  \echo After SET LOCAL ROLE current_user is test.admin@example.com
  SELECT current_user; -- test.admin@example.com
END;
\echo After transaction END current_user is postgres
SELECT current_user; -- postgres


\echo Using a transaction block and subtransactions (savepoints)
SELECT current_user; -- postgres
BEGIN;
  \echo Default current_user is postgres
  SELECT current_user; -- postgres
  SAVEPOINT before_switching;
  \echo Switching to test.admin@example.com
  SET LOCAL ROLE "test.admin@example.com";
  \echo After SET LOCAL ROLE current_user is test.admin@example.com
  SELECT current_user; -- test.admin@example.com
  ROLLBACK TO SAVEPOINT before_switching;
  \echo After RELEASE SAVEPOINT current_user is postgres
  SELECT current_user; -- postgres
END;
\echo After transaction END current_user is postgres
SELECT current_user; -- postgres


\echo Using a DO block
SET client_min_messages TO NOTICE; -- To see the RAISE NOTICE in the DO block
DO $$
BEGIN
  RAISE NOTICE 'Default current_user is %', current_user;
  RAISE NOTICE 'Switching to test.admin@example.com';
  ASSERT current_user = 'postgres';
  SET LOCAL ROLE "test.admin@example.com";
  RAISE NOTICE 'After SET LOCAL ROLE current_user is test.admin@example.com';
  RAISE NOTICE 'current_user is %', current_user;
  ASSERT current_user = 'test.admin@example.com';
END;
$$;
\echo After transaction END current_user is postgres
SELECT current_user; -- postgres


\echo Using a DO block with savepoints
SET client_min_messages TO NOTICE; -- To see the RAISE NOTICE in the DO block
DO $$
BEGIN
  RAISE NOTICE 'Default current_user is %', current_user;
  ASSERT current_user = 'postgres';
  
  -- Use a nested BEGIN/EXCEPTION block for implicit savepoint/rollback
  BEGIN
    RAISE NOTICE 'Switching to test.admin@example.com inside nested block';
    SET LOCAL ROLE "test.admin@example.com";
    RAISE NOTICE 'After SET LOCAL ROLE current_user is %', current_user;
    ASSERT current_user = 'test.admin@example.com';
    
    -- Raise an exception to trigger the implicit rollback
    RAISE EXCEPTION 'Simulating rollback via exception';
    
  EXCEPTION WHEN OTHERS THEN
    -- Catch the exception
    RAISE DEBUG 'Caught exception: %, implicit rollback occurred.', SQLERRM;
  END;
  
  -- Verify that the role change was rolled back
  RAISE NOTICE 'After nested block/exception, current_user is %', current_user;
  ASSERT current_user = 'postgres', 'User should be postgres after implicit rollback';
END;
$$;
\echo After DO block with exception-based rollback, current_user is postgres
SELECT current_user; -- postgres

\echo END: Demonstration of interaction between transaction and roles in the code

\echo 'All SET LOCAL ROLE interaction tests completed successfully!'
