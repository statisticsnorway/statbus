-- Migration 20260712024457: upgrade block terminal resurrection statbus 160
BEGIN;

-- STATBUS-160 — DB FLOOR against terminal-row resurrection. 'completed' means the
-- version VERIFIABLY SERVES — only the upgrade pipeline writes it, after healthCheck
-- passes. No writer may promote a TERMINAL row back to 'completed': that is a lie.
-- The convicting sequence: a fix release C displaces B to 'superseded' (STATBUS-159),
-- C then fails and rolls the box back onto B's binary; a later boot must NOT quietly
-- re-complete the displaced B. Layers 1-2 of STATBUS-160 removed the two Go writers
-- that could (markCurrentVersionCompleted deleted; the install-record upsert narrowed
-- to never-attempted rows); this is the always-add-constraints floor beneath them,
-- and the STATBUS-154 upgrade_state_log trigger audits anything that ever trips it.
--
-- Legal completions are UNAFFECTED: the pipeline is in_progress→completed; install
-- bookkeeping INSERTs a fresh row or completes an available/scheduled one. The
-- deliberate route back to a terminal version is re-dispatch (terminal→scheduled,
-- still legal) → claim → pipeline → an honest completion only if health passes.

CREATE FUNCTION public.upgrade_block_terminal_resurrection()
RETURNS trigger
LANGUAGE plpgsql
AS $upgrade_block_terminal_resurrection$
BEGIN
    -- The trigger's WHEN clause already gates this to exactly the forbidden
    -- transition (terminal → completed); raise the named-remedy error.
    RAISE EXCEPTION
        'upgrade row % (state=%) cannot be completed: terminal rows are not resurrectable — re-dispatch via ./sb upgrade schedule to run it through the pipeline (it completes honestly only if health passes)',
        OLD.id, OLD.state;
    RETURN NEW;
END;
$upgrade_block_terminal_resurrection$;

CREATE TRIGGER upgrade_block_terminal_resurrection_trigger
    BEFORE UPDATE ON public.upgrade
    FOR EACH ROW
    WHEN (NEW.state = 'completed'
          AND OLD.state IN ('superseded', 'failed', 'rolled_back', 'skipped', 'dismissed'))
    EXECUTE FUNCTION public.upgrade_block_terminal_resurrection();

END;
