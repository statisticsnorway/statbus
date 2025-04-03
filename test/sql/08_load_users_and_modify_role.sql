BEGIN;

\i test/setup.sql

-- Create test users with different roles
SELECT public.user_create('test.admin@example.com', 'admin_user'::statbus_role, 'AdminPass123!');
SELECT public.user_create('test.regular@example.com', 'regular_user'::statbus_role, 'RegularPass123!');
SELECT public.user_create('test.restricted@example.com', 'restricted_user'::statbus_role, 'RestrictedPass123!');

-- Verify users were created with correct roles
DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM user_with_role
    WHERE email LIKE '%@example.com';

    IF v_count = 3 THEN
        RAISE NOTICE '✓ Three users created';
    ELSE
        RAISE EXCEPTION 'Expected 3 users, but found % users', v_count;
    END IF;
END $$;

DO $$
DECLARE
    v_statbus_role statbus_role;
BEGIN
    SELECT statbus_role INTO v_statbus_role
    FROM user_with_role
    WHERE email = 'test.admin@example.com';

    IF v_statbus_role = 'admin_user' THEN
        RAISE NOTICE '✓ Super user has correct role';
    ELSE
        RAISE EXCEPTION 'Expected admin_user role, but found %', v_statbus_role;
    END IF;
END $$;

-- Test role update functionality with super user
SAVEPOINT before_admin_user_test;
CALL test.set_user_from_email('test.admin@example.com');

-- Should succeed: super user updating another user's role
UPDATE user_with_role
SET statbus_role = 'regular_user'
WHERE email = 'test.restricted@example.com';

-- Verify the update worked
DO $$
DECLARE
    v_statbus_role statbus_role;
BEGIN
    SELECT statbus_role INTO v_statbus_role
    FROM user_with_role
    WHERE email = 'test.restricted@example.com';

    IF v_statbus_role = 'regular_user' THEN
        RAISE NOTICE '✓ Role update succeeded';
    ELSE
        RAISE EXCEPTION 'Expected regular_user role, but found %', v_statbus_role;
    END IF;
END $$;

ROLLBACK TO SAVEPOINT before_admin_user_test;

-- Test permission checks with regular user
SAVEPOINT before_regular_user_test;
CALL test.set_user_from_email('test.regular@example.com');

-- Should fail: non-super user trying to update roles
DO $$
BEGIN
    BEGIN
        UPDATE user_with_role
        SET statbus_role = 'restricted_user'
        WHERE email = 'test.regular@example.com';
        RAISE EXCEPTION 'Should not reach this point';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE '%Only admin users or system accounts can perform this action%' THEN
                RAISE NOTICE '✓ Permission check working: %', SQLERRM;
            ELSE
                RAISE EXCEPTION 'Unexpected error: %', SQLERRM;
            END IF;
    END;
END $$;

ROLLBACK;
