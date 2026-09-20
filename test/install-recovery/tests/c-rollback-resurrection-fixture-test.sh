#!/bin/bash
# Static ordering guard for the c-rollback resurrection fixture repair. The real
# arc still needs the paid VM run, but this catches reintroducing the contradictory
# premise where C snapshots B's intentionally broken auth_status.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
ARC="$ROOT/test/install-recovery/arcs/c-rollback-resurrection-arc.sh"

python3 - "$ARC" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()

capture = text.index("pg_get_functiondef('public.auth_status()'::regprocedure)")
schedule_b = text.index('── schedule B')
park_proved = text.index('✓ B at-target park landed')
restore = text.index('./sb psql -v ON_ERROR_STOP=1')
pre_c_health = text.index('assert_direct_auth_status_healthy "after park-only fixture cleanup, before C"')
schedule_c = text.index('arc_to "$C_FULL"')

if not (capture < schedule_b < park_proved < restore < pre_c_health < schedule_c):
    raise SystemExit('fixture ordering is not capture canonical body < park B < restore body < prove health < claim C')

for required in (
    'B_ROW_BEFORE_NEUTRALIZE',
    'B_ROW_AFTER_NEUTRALIZE',
    'B_DBMAX_AFTER_NEUTRALIZE',
):
    if required not in text:
        raise SystemExit(f'missing anti-drift assertion: {required}')

if "CREATE OR REPLACE FUNCTION public.auth_status()" in text:
    raise SystemExit('arc hard-codes auth_status instead of restoring the captured source definition')

print('PASS: c-rollback fixture repairs only the park fault before C snapshots healthy B')
PY
