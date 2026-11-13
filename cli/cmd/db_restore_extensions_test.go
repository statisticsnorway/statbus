package cmd

import (
	"os"
	"path/filepath"
	"regexp"
	"testing"
)

// The newest sqlSagaImagePins row is the sql_saga version the current database
// image installs, so a restore of a fresh database's dump creates it at the
// version its rows were written for.
func TestSqlSagaImagePinMatchesDockerfile(t *testing.T) {
	dockerfile, err := os.ReadFile(filepath.Join("..", "..", "postgres", "Dockerfile"))
	if err != nil {
		t.Fatal(err)
	}
	m := regexp.MustCompile(`(?m)^ARG sql_saga_release=v(\S+)$`).FindSubmatch(dockerfile)
	if m == nil {
		t.Fatal("postgres/Dockerfile has no ARG sql_saga_release=v<version> line")
	}
	newest := sqlSagaImagePins[len(sqlSagaImagePins)-1].sqlSaga
	if newest != string(m[1]) {
		t.Errorf("newest sqlSagaImagePins row is %s, postgres/Dockerfile pins sql_saga %s: add a row keyed by the first migration of the release that ships it", newest, m[1])
	}
}

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
		{
			// rune since its 2026-11-08 reset: created on an image pinned at 1.4,
			// so the lifecycle step found sql_saga at the default and wrote no
			// receipt, and the retired update migrations never ran there.
			name: "ledger past STATBUS-533 without a sql_saga receipt is the 533-era pin 1.4",
			audit: auditCopy +
				"1\tjsonb_stats\t\\N\t3.1.0\t2026-11-08\n" +
				"2\tltree\t\\N\t1.3\t2026-11-08\n\\.\n",
			migration: migrationCopy +
				"1\t20240102000000\tx.up.sql\tx\t2026-11-08\n" +
				"900\t20261027221500\ty.up.sql\ty\t2026-11-08\n\\.\n",
			want: "1.4",
		},
		{
			// Created on an image pinned at sql_saga 1.5: no receipt, ledger
			// reaches the first migration of the release that ships 1.5.
			name: "ledger at the 1.5-era release without a sql_saga receipt is 1.5",
			audit: auditCopy +
				"1\tjsonb_stats\t\\N\t3.1.0\t2026-11-20\n\\.\n",
			migration: migrationCopy +
				"900\t20261027221500\ty.up.sql\ty\t2026-11-20\n" +
				"950\t20261111192819\tz.up.sql\tz\t2026-11-20\n\\.\n",
			want: "1.5",
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
