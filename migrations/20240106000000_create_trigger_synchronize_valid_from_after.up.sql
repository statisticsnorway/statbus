BEGIN;

-- Generic trigger function to synchronize valid_from and valid_after columns.
-- Ensures valid_from = valid_after + 1 day.
-- On INSERT:
--   - If only valid_from is given, valid_after is derived.
--   - If only valid_after is given, valid_from is derived.
--   - If both are given, their consistency is checked.
--   - If neither is given, an error is raised.
-- On UPDATE:
--   - If valid_from is changed, valid_after is re-derived.
--   - If valid_after is changed, valid_from is re-derived.
--   - Prevents setting either to NULL.
--   - Checks for consistency if both are somehow explicitly set to conflicting values.
CREATE OR REPLACE FUNCTION public.synchronize_valid_from_after()
RETURNS TRIGGER LANGUAGE plpgsql AS $synchronize_valid_from_after$
BEGIN
    -- For INSERT operations
    IF TG_OP = 'INSERT' THEN
        IF NEW.valid_from IS NOT NULL AND NEW.valid_after IS NULL THEN
            NEW.valid_after := NEW.valid_from - INTERVAL '1 day';
        ELSIF NEW.valid_after IS NOT NULL AND NEW.valid_from IS NULL THEN
            NEW.valid_from := NEW.valid_after + INTERVAL '1 day';
        ELSIF NEW.valid_from IS NOT NULL AND NEW.valid_after IS NOT NULL THEN
            IF NEW.valid_after != (NEW.valid_from - INTERVAL '1 day') THEN
                RAISE EXCEPTION 'On INSERT, valid_from and valid_after are inconsistent. Expected valid_after = valid_from - 1 day. Got valid_from=%, valid_after=%', NEW.valid_from, NEW.valid_after;
            END IF;
        ELSE -- Both are NULL
            RAISE EXCEPTION 'On INSERT, either valid_from or valid_after must be provided for table %', TG_TABLE_NAME;
        END IF;

    -- For UPDATE operations
    ELSIF TG_OP = 'UPDATE' THEN
        -- Determine which field was the primary source of change, or if they are conflicting.
        -- Precedence: If valid_from is explicitly set to a non-NULL value, it drives the change.
        -- Otherwise, if valid_after is explicitly set to a non-NULL value, it drives the change.
        IF NEW.valid_from IS NOT NULL AND NEW.valid_from IS DISTINCT FROM OLD.valid_from THEN
            NEW.valid_after := NEW.valid_from - INTERVAL '1 day';
            -- If valid_after was also explicitly set in the UPDATE statement and it's inconsistent with the new valid_from, raise error.
            IF NEW.valid_after IS DISTINCT FROM OLD.valid_after AND NEW.valid_after IS NOT NULL AND NEW.valid_after != (NEW.valid_from - INTERVAL '1 day') THEN
                 RAISE EXCEPTION 'On UPDATE for table %, conflicting explicit values for valid_from and valid_after. With valid_from=%, expected valid_after=%. Got valid_after=%', 
                                 TG_TABLE_NAME, NEW.valid_from, NEW.valid_from - INTERVAL '1 day', NEW.valid_after;
            END IF;
        ELSIF NEW.valid_after IS NOT NULL AND NEW.valid_after IS DISTINCT FROM OLD.valid_after THEN
            -- This case handles when valid_after is set to non-NULL, and valid_from was either not changed,
            -- or was changed but to NULL (which would be an error caught later if valid_after also became NULL).
            NEW.valid_from := NEW.valid_after + INTERVAL '1 day';
        ELSIF (NEW.valid_from IS NULL AND NEW.valid_from IS DISTINCT FROM OLD.valid_from) OR 
              (NEW.valid_after IS NULL AND NEW.valid_after IS DISTINCT FROM OLD.valid_after) THEN
            -- This catches attempts to set either field to NULL.
            RAISE EXCEPTION 'On UPDATE for table %, neither valid_from nor valid_after can be set to NULL. Attempted valid_from=%, valid_after=%', TG_TABLE_NAME, NEW.valid_from, NEW.valid_after;
        END IF;
        
        -- Final check: after all modifications, ensure both are non-NULL and consistent.
        IF NEW.valid_from IS NULL OR NEW.valid_after IS NULL THEN
            RAISE EXCEPTION 'On UPDATE for table %, valid_from and valid_after must result in non-NULL values. Got valid_from=%, valid_after=%', TG_TABLE_NAME, NEW.valid_from, NEW.valid_after;
        END IF;

        IF NEW.valid_after != (NEW.valid_from - INTERVAL '1 day') THEN
            -- This should ideally not be reached if above logic is correct, but serves as a safeguard.
            RAISE EXCEPTION 'On UPDATE for table %, derived valid_from and valid_after are inconsistent. Got valid_from=%, valid_after=%', TG_TABLE_NAME, NEW.valid_from, NEW.valid_after;
        END IF;
    END IF;
    RETURN NEW;
END;
$synchronize_valid_from_after$;

COMMIT;
-- For DOWN migration:
-- DROP FUNCTION public.synchronize_valid_from_after();
-- Note: Triggers on tables would also need to be dropped.
-- Reverting the GENERATED ALWAYS columns is more complex and would require data backfill if strategy changes.
