BEGIN;

-- Create test users with different roles
SELECT public.statbus_user_create('test.super@example.com', 'super_user'::statbus_role_type, 'SuperPass123!');
SELECT public.statbus_user_create('test.regular@example.com', 'regular_user'::statbus_role_type, 'RegularPass123!');
SELECT public.statbus_user_create('test.restricted@example.com', 'restricted_user'::statbus_role_type, 'RestrictedPass123!');

-- Verify users were created with correct roles
DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM statbus_user_with_email_and_role
    WHERE email LIKE '%@example.com';

    IF v_count = 3 THEN
        RAISE NOTICE '✓ Three users created';
    ELSE
        RAISE EXCEPTION 'Expected 3 users, but found % users', v_count;
    END IF;
END $$;

DO $$
DECLARE
    v_role_type statbus_role_type;
BEGIN
    SELECT role_type INTO v_role_type
    FROM statbus_user_with_email_and_role
    WHERE email = 'test.super@example.com';

    IF v_role_type = 'super_user' THEN
        RAISE NOTICE '✓ Super user has correct role';
    ELSE
        RAISE EXCEPTION 'Expected super_user role, but found %', v_role_type;
    END IF;
END $$;

-- Test role update functionality with super user
SAVEPOINT before_super_user_test;
CALL test.set_user_from_email('test.super@example.com');

-- Should succeed: super user updating another user's role
UPDATE statbus_user_with_email_and_role
SET role_type = 'regular_user'
WHERE email = 'test.restricted@example.com';

-- Verify the update worked
DO $$
DECLARE
    v_role_type statbus_role_type;
BEGIN
    SELECT role_type INTO v_role_type
    FROM statbus_user_with_email_and_role
    WHERE email = 'test.restricted@example.com';

    IF v_role_type = 'regular_user' THEN
        RAISE NOTICE '✓ Role update succeeded';
    ELSE
        RAISE EXCEPTION 'Expected regular_user role, but found %', v_role_type;
    END IF;
END $$;

ROLLBACK TO SAVEPOINT before_super_user_test;

-- Test permission checks with regular user
SAVEPOINT before_regular_user_test;
CALL test.set_user_from_email('test.regular@example.com');

-- Should fail: non-super user trying to update roles
DO $$
BEGIN
    BEGIN
        UPDATE statbus_user_with_email_and_role
        SET role_type = 'restricted_user'
        WHERE email = 'test.regular@example.com';
        RAISE EXCEPTION 'Should not reach this point';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE '%Only super users or system accounts can perform this action%' THEN
                RAISE NOTICE '✓ Permission check working: %', SQLERRM;
            ELSE
                RAISE EXCEPTION 'Unexpected error: %', SQLERRM;
            END IF;
    END;
END $$;

ROLLBACK;
