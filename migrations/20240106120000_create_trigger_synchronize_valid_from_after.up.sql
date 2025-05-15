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
        -- Case 1: Both valid_from and valid_after are being explicitly changed by the UPDATE statement
        IF NEW.valid_from IS DISTINCT FROM OLD.valid_from AND NEW.valid_after IS DISTINCT FROM OLD.valid_after THEN
            IF NEW.valid_from IS NULL OR NEW.valid_after IS NULL THEN
                RAISE EXCEPTION 'On UPDATE for table %, when changing both valid_from and valid_after, neither can be set to NULL. Attempted valid_from=%, valid_after=%', TG_TABLE_NAME, NEW.valid_from, NEW.valid_after;
            END IF;
            IF NEW.valid_after != (NEW.valid_from - INTERVAL '1 day') THEN
                RAISE EXCEPTION 'On UPDATE for table %, conflicting explicit values for valid_from and valid_after. With valid_from=%, expected valid_after=%. Got valid_after=%', 
                                 TG_TABLE_NAME, NEW.valid_from, NEW.valid_from - INTERVAL '1 day', NEW.valid_after;
            END IF;
            -- If they are consistent, the values are fine as they are and will be used.
        -- Case 2: Only valid_from is being explicitly changed (and valid_after was not, or its change was not distinct)
        ELSIF NEW.valid_from IS DISTINCT FROM OLD.valid_from THEN
            IF NEW.valid_from IS NULL THEN
                RAISE EXCEPTION 'On UPDATE for table %, valid_from cannot be set to NULL. Attempted valid_from=%, valid_after=%', TG_TABLE_NAME, NEW.valid_from, NEW.valid_after;
            END IF;
            NEW.valid_after := NEW.valid_from - INTERVAL '1 day';
        -- Case 3: Only valid_after is being explicitly changed (and valid_from was not, or its change was not distinct)
        ELSIF NEW.valid_after IS DISTINCT FROM OLD.valid_after THEN
            IF NEW.valid_after IS NULL THEN
                RAISE EXCEPTION 'On UPDATE for table %, valid_after cannot be set to NULL. Attempted valid_from=%, valid_after=%', TG_TABLE_NAME, NEW.valid_from, NEW.valid_after;
            END IF;
            NEW.valid_from := NEW.valid_after + INTERVAL '1 day';
        -- Case 4: Neither valid_from nor valid_after is being distinctly changed by the UPDATE statement's SET clause.
        -- Their values are taken from OLD if not specified. We must ensure they are not NULL and remain consistent.
        ELSE
            IF NEW.valid_from IS NULL OR NEW.valid_after IS NULL THEN
                 RAISE EXCEPTION 'On UPDATE for table %, valid_from and valid_after cannot be NULL (and were not changed by SET clause). Got valid_from=%, valid_after=%', TG_TABLE_NAME, NEW.valid_from, NEW.valid_after;
            END IF;
            IF NEW.valid_after != (NEW.valid_from - INTERVAL '1 day') THEN
                 RAISE EXCEPTION 'On UPDATE for table %, existing valid_from and valid_after are inconsistent (and were not changed by SET clause). Got valid_from=%, valid_after=%', TG_TABLE_NAME, NEW.valid_from, NEW.valid_after;
            END IF;
        END IF;
        
        -- Final safeguard checks after all logic.
        IF NEW.valid_from IS NULL OR NEW.valid_after IS NULL THEN
            -- This should ideally not be reached if the specific cases above correctly handle NULL assignments.
            RAISE EXCEPTION 'On UPDATE for table %, valid_from and valid_after must result in non-NULL values. Got valid_from=%, valid_after=%', TG_TABLE_NAME, NEW.valid_from, NEW.valid_after;
        END IF;

        IF NEW.valid_after != (NEW.valid_from - INTERVAL '1 day') THEN
            -- This should also ideally not be reached if the logic correctly establishes consistency.
            RAISE EXCEPTION 'On UPDATE for table %, derived valid_from and valid_after are inconsistent after all processing. Got valid_from=%, valid_after=%', TG_TABLE_NAME, NEW.valid_from, NEW.valid_after;
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
