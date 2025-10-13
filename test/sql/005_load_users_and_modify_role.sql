BEGIN;

\i test/setup.sql

-- Create test users with different roles
SELECT public.user_create(p_display_name => 'Example Admin', p_email => 'test.admin@example.com', p_statbus_role => 'admin_user'::statbus_role, p_password => 'AdminPass123!');
SELECT public.user_create(p_display_name => 'Example Regular', p_email => 'test.regular@example.com', p_statbus_role => 'regular_user'::statbus_role, p_password => 'RegularPass123!');
SELECT public.user_create(p_display_name => 'Example Restricted', p_email => 'test.restricted@example.com', p_statbus_role => 'restricted_user'::statbus_role, p_password => 'RestrictedPass123!');

-- Verify users were created with correct roles
DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM public.user
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
    FROM public.user
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
SELECT current_user;

-- Should succeed: super user updating another user's role
UPDATE public.user
SET statbus_role = 'regular_user'
WHERE email = 'test.restricted@example.com';

-- Verify the update worked
DO $$
DECLARE
    v_statbus_role statbus_role;
BEGIN
    SELECT statbus_role INTO v_statbus_role
    FROM public.user
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
SELECT current_user;
CALL test.set_user_from_email('test.regular@example.com');
SELECT current_user;

-- Should fail: non-super user trying to update roles
DO $$
BEGIN
    BEGIN
        UPDATE public.user
        SET statbus_role = 'admin_user' -- User tries to upgrade his own role!
        WHERE email = 'test.regular@example.com';
        IF FOUND THEN
          RAISE EXCEPTION 'User upgraded his own role!';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE '%Permission denied: Cannot assign role admin_user.%' THEN
                RAISE NOTICE '✓ Permission check working: %', SQLERRM;
            ELSE
                RAISE EXCEPTION 'Unexpected error: %', SQLERRM;
            END IF;
    END;
END $$;

ROLLBACK;
