-- Down Migration 20260703104910: exempt authenticator role from read only window postgrest listener statbus_110
BEGIN;

ALTER ROLE authenticator RESET default_transaction_read_only;

END;
