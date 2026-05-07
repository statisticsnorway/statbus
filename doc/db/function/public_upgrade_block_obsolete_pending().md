```sql
CREATE OR REPLACE FUNCTION public.upgrade_block_obsolete_pending()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Strict committed_at comparison (>) mirrors upgrade_supersede_older's
    -- "committed_at < _committed" — equal-timestamp rows are NOT ancestors
    -- of each other (no strict ordering), so the trigger leaves them alone.
    -- This matters for test fixtures with deterministic shared timestamps;
    -- in production, distinct commit timestamps make the distinction moot.
    IF NEW.state IN ('available', 'scheduled') THEN
        IF EXISTS (
            SELECT 1 FROM public.upgrade older
             WHERE older.state = 'completed'
               AND older.commit_sha != NEW.commit_sha
               AND older.release_status >= NEW.release_status
               AND older.committed_at > NEW.committed_at
        ) THEN
            NEW.state := 'superseded';
            NEW.superseded_at := COALESCE(NEW.superseded_at, now());
        END IF;
    END IF;
    RETURN NEW;
END;
$function$
```
