-- Test Template for Error Handling in PostgreSQL pg_regress Tests
-- Minimal working examples.

\echo '>>> Test Suite: Error Handling Patterns (Minimal) <<<'
SET client_min_messages TO NOTICE; -- Show RAISE NOTICE messages

-- =============================================================================
-- Pattern A: Catching ASSERT failures and other errors within a DO block
-- using a nested BEGIN/EXCEPTION/END sub-block.
-- This isolates the test unit. The sub-block acts like a savepoint.
-- =============================================================================
\echo '--- Pattern A: Nested BEGIN/EXCEPTION/END within a DO block (for ASSERTs) ---'

-- Scenario A.1: Passing Test
\echo '-- Scenario A.1: Passing Test --'
DO $$
BEGIN
    -- This outer BEGIN is part of the DO block structure.
    -- The nested BEGIN/EXCEPTION/END provides the error catching.
    BEGIN
        RAISE NOTICE 'Test A.1: Starting scenario that should pass.';
        CREATE TEMP TABLE temp_A1 (id int);
        INSERT INTO temp_A1 VALUES (1);
        ASSERT (SELECT COUNT(*) FROM temp_A1) = 1, 'Test A.1: Temp table should have 1 row.';
        RAISE NOTICE 'Test A.1: Scenario PASSED.';
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'Test A.1: Scenario FAILED (unexpected): %', SQLERRM;
            -- Effects of this sub-block before the error are implicitly rolled back.
    END; -- End of nested error-catching block
    DROP TABLE IF EXISTS temp_A1; -- Cleanup, will run if sub-block didn't error or error was caught.
END; -- End of DO block
$$;

-- Scenario A.2: Failing Test (ASSERT failure)
\echo '-- Scenario A.2: Failing Test (ASSERT failure) --'
DO $$
BEGIN
    BEGIN
        RAISE NOTICE 'Test A.2: Starting scenario with a failing ASSERT.';
        CREATE TEMP TABLE temp_A2 (id int);
        ASSERT 1 = 0, 'Test A.2: This assertion will fail.';
        RAISE NOTICE 'Test A.2: Scenario PASSED (this should not print).';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN -- Specific condition for assert failures (SQLSTATE P0004)
            RAISE NOTICE 'Test A.2: Scenario FAILED as expected (ASSERT_FAILURE): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test A.2: Scenario FAILED with unexpected error: %', SQLERRM;
    END;
    DROP TABLE IF EXISTS temp_A2; -- temp_A2 should not exist if created inside the rolled-back sub-block
END;
$$;

-- Check transaction state after Pattern A failure (A.2)
-- This DO block is separate and should execute if the main transaction is alive.
\echo '-- Checking transaction state after Pattern A failure --'
DO $$
BEGIN
    BEGIN
        CREATE TEMP TABLE temp_check_A (id int);
        INSERT INTO temp_check_A VALUES (1);
        ASSERT (SELECT COUNT(*) FROM temp_check_A) = 1, 'Main transaction should still be active after Pattern A failure.';
        RAISE NOTICE 'Transaction check after Pattern A: Main transaction is active.';
        DROP TABLE temp_check_A;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'Transaction check after Pattern A: FAILED - %', SQLERRM;
    END;
END;
$$;

-- =============================================================================
-- Pattern B: DO block with its own EXCEPTION handling for PL/pgSQL runtime errors
-- This pattern catches errors like RAISE EXCEPTION.
-- It does NOT catch ASSERT failures in its EXCEPTION clause; ASSERT failures abort the DO block.
-- =============================================================================
\echo '--- Pattern B: DO block with internal EXCEPTION handling (for RAISE, etc.) ---'

-- Scenario B.1: Passing Test
\echo '-- Scenario B.1: Passing Test --'
DO $$
BEGIN
    RAISE NOTICE 'Test B.1: Starting scenario that should pass.';
    CREATE TEMP TABLE temp_B1 (id int);
    INSERT INTO temp_B1 VALUES (1);
    IF (SELECT COUNT(*) FROM temp_B1) <> 1 THEN
        RAISE EXCEPTION 'Test B.1: Temp table count incorrect.';
    END IF;
    RAISE NOTICE 'Test B.1: Scenario PASSED.';
    DROP TABLE temp_B1;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Test B.1: Scenario FAILED (unexpected): %', SQLERRM;
END;
$$;

-- Scenario B.2: Failing Test (RAISE EXCEPTION)
\echo '-- Scenario B.2: Failing Test (RAISE EXCEPTION) --'
DO $$
BEGIN
    RAISE NOTICE 'Test B.2: Starting scenario with a RAISE EXCEPTION.';
    CREATE TEMP TABLE temp_B2 (id int);
    RAISE EXCEPTION 'Test B.2: This is an intentional exception.' USING ERRCODE = 'P0001';
    RAISE NOTICE 'Test B.2: Scenario PASSED (this should not print).';
    DROP TABLE IF EXISTS temp_B2; -- Will not be reached
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Test B.2: Scenario FAILED as expected: % (Code: %)', SQLERRM, SQLSTATE;
        -- Temp table temp_B2 creation would be rolled back due to DO block's implicit savepoint behavior on exception.
END;
$$;
DROP TABLE IF EXISTS temp_B2; -- Cleanup if somehow not dropped by the DO block's rollback.

-- Scenario B.3: ASSERT failure in a DO block (NOT caught by its own EXCEPTION clause)
-- This DO block will error out. The main pg_regress transaction might abort
-- if this error is not handled by an outer mechanism (like Pattern A).
-- For this template, we let it error to demonstrate the behavior.
\echo '-- Scenario B.3: ASSERT failure in a DO block (EXPECTS DO block to ERROR out) --'
DO $$
BEGIN
    RAISE NOTICE 'Test B.3: Starting scenario with an ASSERT that will abort this DO block.';
    CREATE TEMP TABLE temp_B3_inner (id int);
    ASSERT 1 = 0, 'Test B.3: This ASSERT will fail and abort this DO block.';
    RAISE NOTICE 'Test B.3: Inner DO block PASSED (this should not print).';
EXCEPTION
    WHEN OTHERS THEN
        -- This EXCEPTION clause in THIS DO block will NOT catch the ASSERT failure.
        RAISE NOTICE 'Test B.3: This DO block''s EXCEPTION caught (SHOULD NOT HAPPEN FOR ASSERT): %', SQLERRM;
END;
$$;
-- If the above DO block errored and aborted the main transaction, the following 'Transaction check' might not run
-- or might run in a new transaction, depending on pg_regress behavior.
DROP TABLE IF EXISTS temp_B3_inner; -- Cleanup

-- Scenario B.4: Catching an ASSERT failure from "inner" logic using an outer Pattern A structure.
-- The "inner" logic is directly part of the outer block's BEGIN/EXCEPTION.
\echo '-- Scenario B.4: Catching ASSERT from inner logic with outer Pattern A structure --'
DO $$ -- Outer DO block (Pattern A style)
BEGIN
    BEGIN -- Nested BEGIN/EXCEPTION for the outer DO block, this will catch the ASSERT
        RAISE NOTICE 'Test B.4: Outer DO block started, will execute inner logic with failing ASSERT.';
        
        -- "Inner" logic starts here
        RAISE NOTICE 'Test B.4: Inner logic starting, will ASSERT fail.';
        CREATE TEMP TABLE temp_B4 (id int);
        ASSERT 1 = 0, 'Test B.4: This ASSERT from inner logic will fail.';
        -- "Inner" logic ends here
        
        RAISE NOTICE 'Test B.4: After inner logic (this should not print if ASSERT failed).';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test B.4: Outer DO EXCEPTION caught ASSERT_FAILURE from inner logic as expected: %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test B.4: Outer DO EXCEPTION caught some other error from inner logic: %', SQLERRM;
    END; -- End of nested BEGIN/EXCEPTION for outer DO
    DROP TABLE IF EXISTS temp_B4; -- temp_B4 should not exist if created in the rolled-back sub-block
END; -- End of Outer DO block
$$;


-- Check transaction state after Pattern B tests
\echo '-- Checking transaction state after Pattern B tests (esp. after B.3''s expected error) --'
DO $$
BEGIN
    BEGIN
        CREATE TEMP TABLE temp_check_B (id int);
        INSERT INTO temp_check_B VALUES (1);
        ASSERT (SELECT COUNT(*) FROM temp_check_B) = 1, 'Main transaction should still be active after Pattern B tests.';
        RAISE NOTICE 'Transaction check after Pattern B: Main transaction is active.';
        DROP TABLE temp_check_B;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'Transaction check after Pattern B: FAILED - %', SQLERRM;
    END;
END;
$$;

\echo '>>> Test Suite: Error Handling Patterns (Minimal) Complete <<<'
