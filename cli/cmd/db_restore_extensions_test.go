package cmd

import "testing"

// STATBUS-542: ./sb db restore installs sql_saga at the version the dump was
// made with, so the dump's catalog rows load into the layout they were
// written for; the extension lifecycle step then updates it to the image
// default. These cases are the dump contents the restore reads that version
// from.
func TestDumpSqlSagaVersion(t *testing.T) {
	const migrationCopy = "COPY db.migration (id, version, filename, description, applied_at) FROM stdin;\n"
	const auditCopy = "COPY db.extension_upgrade (id, extension, from_version, to_version, applied_at) FROM stdin;\n"
	cases := []struct {
		name      string
		audit     string
		migration string
		want      string
	}{
		{
			name:      "audit receipt names the version (dump made after STATBUS-533)",
			audit:     auditCopy + "1\tsql_saga\t1.3\t1.4\t2026-10-28 02:16:33+00\n\\.\n",
			migration: migrationCopy + "1\t20240102000000\tx.up.sql\tx\t2026-01-01\n\\.\n",
			want:      "1.4",
		},
		{
			name: "newest sql_saga receipt wins, other extensions ignored",
			audit: auditCopy +
				"1\tsql_saga\t\\N\t1.4\t2026-10-28\n" +
				"2\tjsonb_stats\t\\N\t3.0.0\t2026-10-28\n" +
				"3\tsql_saga\t1.4\t1.5\t2026-11-28\n\\.\n",
			want: "1.5",
		},
		{
			name:      "legacy ledger row of the sql_saga 1.1 update migration",
			migration: migrationCopy + "628\t20261015163419\t20261015163419_sql_saga_1_1.up.sql\tsql_saga_1_1\t2026-10-15\n\\.\n",
			want:      "1.1",
		},
		{
			name: "legacy ledger: the newest sql_saga update migration wins",
			migration: migrationCopy +
				"628\t20261015163419\ta.up.sql\ta\t2026-10-15\n" +
				"700\t20261021130641\tb.up.sql\tb\t2026-10-21\n\\.\n",
			want: "1.3",
		},
		{
			name:      "legacy ledger without any sql_saga update migration is 1.0",
			migration: migrationCopy + "1\t20240102000000\tx.up.sql\tx\t2026-01-01\n\\.\n",
			want:      "1.0",
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := dumpSqlSagaVersion(c.audit, c.migration); got != c.want {
				t.Errorf("dumpSqlSagaVersion() = %q, want %q", got, c.want)
			}
		})
	}
}
