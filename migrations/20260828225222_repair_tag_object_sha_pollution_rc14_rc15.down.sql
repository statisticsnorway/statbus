-- Down migration: no-op.
--
-- The up migration repairs public.upgrade rows that stored an ANNOTATED
-- TAG OBJECT's SHA in commit_sha where the COMMIT it points at belongs
-- (STATBUS-304). Reversing it would re-write the wrong object back into
-- commit_sha — reintroducing the exact defect this migration exists to
-- fix, on purpose, which is never correct.
--
-- This is a one-way data fix; the only reversible counterpart is the
-- structural guarantee that no current discovery path can write this
-- defect again (STATBUS-255's git-based discovery peels correctly, and
-- CommitLookup.RevParse appends ^{commit} explicitly — verified, not
-- reasoned, per STATBUS-304 comment #2). Same pattern as
-- 20260425163029_dismiss_corrupt_upgrade_lifecycle_rows.down.sql.

SELECT 1;
