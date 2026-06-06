-- Harness-only: scenario 12 (C12 / Race B regression net).
-- Written to the VM working copy only — NOT committed to production migrations.
-- Ensures ./sb migrate up has at least one pending migration so
-- inject.StallHere in runPsqlFile is reachable regardless of whether the
-- HEAD seed already captured all production migrations (db-seed always
-- tracks HEAD, so a version-delta install path can't rely on a gap).
SELECT 1;
