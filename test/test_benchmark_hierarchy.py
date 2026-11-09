"""Offline regression tests for benchmark snapshots and measured job acceptance."""
import contextlib
from datetime import date
import importlib.util
import io
import logging
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch

spec = importlib.util.spec_from_file_location("import_benchmark", os.environ.get(
    "BENCHMARK_MODULE_PATH", Path(__file__).with_name("import_benchmark.py")))
benchmark = importlib.util.module_from_spec(spec)
with patch("logging.FileHandler", return_value=logging.NullHandler()), patch.object(Path, "mkdir"):
    spec.loader.exec_module(benchmark)


class Cursor:
    def __init__(self, snapshot, missing=None):
        self.snapshot, self.missing, self.calls = snapshot, missing, []
        self.row = None

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass

    def execute(self, query, params=None):
        self.calls.append((query, params))
        if "FROM public.statistical_unit AS su" in query:
            kind = "enterprise" if "'enterprise'" in query else "legal_unit"
            self.row = ((101 if kind == "enterprise" else 202),) if (
                params == (self.snapshot, self.snapshot) and self.missing != kind) else None
        elif query.startswith("EXPLAIN ANALYZE"):
            self.row = None
        elif "SELECT now()" in query:
            self.row = ("fixture time",)
        else:
            raise AssertionError(query)

    def fetchone(self):
        return self.row

    def fetchall(self):
        return [("Execution Time: 1 ms",)]


class Connection:
    def __init__(self, cursor):
        self.cur, self.closed = cursor, False

    def cursor(self):
        return self.cur

    def close(self):
        self.closed = True


class HierarchyTests(unittest.TestCase):
    def test_snapshot_resolution(self):
        day = date(2026, 11, 7)
        jobs = [{"default_valid_from": day}, {"default_valid_from": day}]
        self.assertEqual(benchmark.hierarchy_snapshot(jobs, {"valid_from": "2026-11-07", "year": None}), day)
        self.assertEqual(benchmark.hierarchy_snapshot(jobs, {"valid_from": None, "year": None}), day)
        self.assertEqual(benchmark.hierarchy_snapshot([{"default_valid_from": date(2024, 1, 1)}],
                                                      {"valid_from": None, "year": "2024"}), date(2024, 1, 1))
        for bad_jobs, requested in (([], {}), ([{"default_valid_from": None}], {}),
                                    (jobs + [{"default_valid_from": date(2025, 1, 1)}], {}),
                                    (jobs, {"valid_from": "2025-01-01"})):
            with self.subTest(jobs=bad_jobs), self.assertRaises(ValueError):
                benchmark.hierarchy_snapshot(bad_jobs, requested)

    def test_date_selects_valid_units_and_all_four_real_calls(self):
        day = date(2026, 11, 7)
        cursor = Cursor(day)
        connection = Connection(cursor)
        with patch.object(benchmark, "get_conn", return_value=connection), contextlib.redirect_stdout(io.StringIO()):
            result = benchmark.run_hierarchy_benchmarks(day, write_perf=False)
        self.assertEqual(result["status"], "completed")
        self.assertEqual(result["snapshot_date"], day)
        self.assertEqual((result["enterprise_id"], result["legal_unit_id"]), (101, 202))
        probes = [(query, params) for query, params in cursor.calls if query.startswith("EXPLAIN ANALYZE")]
        self.assertEqual(len(probes), 4)
        expected = {("statistical_unit_stats", "legal_unit", 202), ("statistical_unit_stats", "enterprise", 101),
                    ("relevant_statistical_units", "legal_unit", 202), ("relevant_statistical_units", "enterprise", 101)}
        observed = {(function, kind, params[0]) for query, params in probes
                    for function in ("statistical_unit_stats", "relevant_statistical_units")
                    for kind in ("legal_unit", "enterprise")
                    if f"public.{function}(" in query and f"'{kind}'" in query and params[1] == day}
        self.assertEqual(observed, expected)
        self.assertTrue(connection.closed)

    def test_missing_valid_unit_is_not_reported_as_completed(self):
        day = date(2026, 11, 7)
        for missing in ("enterprise", "legal_unit"):
            cursor = Cursor(day, missing)
            connection = Connection(cursor)
            with self.subTest(missing=missing), patch.object(benchmark, "get_conn", return_value=connection), \
                    contextlib.redirect_stdout(io.StringIO()):
                result = benchmark.run_hierarchy_benchmarks(day, write_perf=False)
            self.assertEqual(result["status"], "not_run")
            self.assertIn(missing, result["reason"])
            self.assertTrue(connection.closed)
            self.assertEqual(sum(q.startswith("EXPLAIN ANALYZE") for q, _ in cursor.calls), 0)


class CallerPathTests(unittest.TestCase):
    def test_worker_path_uses_observed_date_for_all_probes(self):
        day = date(2026, 11, 7)
        cursor = Cursor(day)
        connection = Connection(cursor)

        class WorkerCursor:
            def __enter__(self):
                self.calls = 0
                return self
            def __exit__(self, *args):
                pass
            def execute(self, query, *args):
                self.calls += 1
            def fetchall(self):
                return [[("completed", 3)], [], [("derive_statistical_unit", 28, 280, 10, 10, 10)]][self.calls - 1]
            def fetchone(self):
                return (28,)

        class WorkerConnection:
            def cursor(self):
                return WorkerCursor()
            def close(self):
                pass

        expected = [{"id": n, "slug": f"job-{n}", "uploaded_rows": 1} for n in range(3)]
        observation = {"jobs": [{**job, "default_valid_from": day, "state": "finished", "total_rows": 1,
                                 "imported_rows": 1, "error_count": 0,
                                 "actual_data_rows": {"total": 1, "by_state": {"processed": 1}}}
                                for job in expected],
                       "failed_task_count": 0, "processing_overlap": benchmark.interval_summary([])}
        observation["jobs"].append({"id": 99, "default_valid_from": date(2020, 1, 1)})
        result = {"requested_validity": {"valid_from": day.isoformat(), "year": None}, "expected_jobs": expected}
        output = io.StringIO()
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(benchmark, "WORKSPACE", Path(directory).absolute()), \
                patch.object(benchmark, "run_worker", return_value=(0, [], 1)), \
                patch.object(benchmark, "LAST_WORKER_RUN", {"timed_out": False}), \
                patch.object(benchmark, "collect_observation", return_value=observation), \
                patch.object(benchmark, "get_conn", side_effect=[WorkerConnection(), connection]), \
                patch.object(benchmark, "check_dataset", return_value={"status": "passed", "passed": True}), \
                patch.object(benchmark, "check_consistency", return_value=(True, "A/B/C passed")), \
                patch.object(benchmark, "run_repeated_call_benchmarks", return_value=True), \
                contextlib.redirect_stdout(output):
            success = benchmark.run_concurrent_test(result=result, dataset="downloads")
        self.assertTrue(success)
        selectors = [(q, p) for q, p in cursor.calls if "FROM public.statistical_unit AS su" in q]
        probes = [(q, p) for q, p in cursor.calls if q.startswith("EXPLAIN ANALYZE")]
        self.assertEqual(len(probes), 4, "expected four hierarchy probes at the observed snapshot")
        self.assertEqual([p for _, p in selectors], [(day, day), (day, day)])
        self.assertEqual([p for _, p in probes], [(202, day), (101, day), (202, day), (101, day)])
        self.assertEqual(result["checks"]["hierarchy"]["status"], "completed")
        self.assertEqual(result["checks"]["hierarchy"]["snapshot_date"], day)
        self.assertIn("28 derive_statistical_unit task(s)", output.getvalue())

    def test_worker_success_requires_each_expected_job_finished_and_accounted(self):
        day = date(2026, 11, 7)
        expected = [{"id": n, "slug": slug, "uploaded_rows": 10} for n, slug in enumerate(
            ("import_hovedenhet_2025", "import_underenhet_2025", "import_roller_2025"), 1)]
        jobs = [{**identity, "default_valid_from": day, "state": "finished", "total_rows": 10,
                 "imported_rows": 8, "error_count": 2, "actual_data_rows": {"total": 10, "by_state": {"processed": 8, "error": 2},
                                                            "processed": 8, "error": 2}}
                for identity in expected]

        class WorkerCursor:
            def __enter__(self):
                self.results = iter([[('completed', 2)], [], []])
                return self
            def __exit__(self, *args):
                pass
            def execute(self, *args):
                pass
            def fetchall(self):
                return next(self.results)

        class WorkerConnection:
            def cursor(self):
                return WorkerCursor()
            def close(self):
                pass

        variants = [("finished with accepted rejection rows", jobs, True),
                    ("failed", [{**jobs[0], "state": "failed"}] + jobs[1:], False),
                    ("unfinished", [{**jobs[0], "state": "processing_data"}] + jobs[1:], False),
                    ("missing", jobs[:-1], False),
                    ("fatal error", [{**jobs[0], "error": "fatal"}] + jobs[1:], False),
                    ("shrunk consistently", [{**jobs[0], "total_rows": 8,
                        "actual_data_rows": {"total": 8, "by_state": {"processed": 8}}}] + jobs[1:], False),
                    ("counter mismatch", [{**jobs[0], "imported_rows": 7}] + jobs[1:], False),
                    ("rejection count mismatch", [{**jobs[0], "error_count": 1}] + jobs[1:], False),
                    ("pending rows", [{**jobs[0], "actual_data_rows": {"total": 10,
                        "by_state": {"processed": 8, "error": 1, "processing": 1}, "processed": 8, "error": 1}}] + jobs[1:], False)]
        for label, observed, wanted in variants:
            with self.subTest(label=label), patch.object(benchmark, "run_worker", return_value=(0, [], 1)), \
                    patch.object(benchmark, "LAST_WORKER_RUN", {"timed_out": False}), \
                    patch.object(benchmark, "collect_observation", return_value={"jobs": observed, "failed_task_count": 0,
                        "processing_overlap": benchmark.interval_summary([])}), \
                    patch.object(benchmark, "get_conn", return_value=WorkerConnection()), \
                    patch.object(benchmark, "check_dataset", return_value={"status": "not_applicable", "passed": True}), \
                    patch.object(benchmark, "check_consistency", return_value=(True, "A/B/C passed")), \
                    patch.object(benchmark, "run_hierarchy_benchmarks", return_value={"status": "not_run"}), \
                    patch.object(benchmark, "run_repeated_call_benchmarks", return_value=True), \
                    contextlib.redirect_stdout(io.StringIO()):
                result = {"expected_jobs": expected}
                actual = benchmark.run_concurrent_test(result=result, dataset="downloads")
                self.assertEqual(actual, wanted, label)


class ReplayProgressTests(unittest.TestCase):
    def test_each_replayed_call_reports_command_and_index(self):
        class ReplayCursor:
            def __enter__(self):
                self.calls = []
                return self
            def __exit__(self, *args):
                pass
            def execute(self, query, params):
                self.calls.append((query, params))
            def fetchall(self):
                return [("derive_child", "public.handler", {"secret_marker": "not_for_log"})]

        cursor = ReplayCursor()
        connection = Connection(cursor)
        connection.rollback = lambda: None
        output = io.StringIO()
        adapter = SimpleNamespace(extras=SimpleNamespace(Json=lambda value: value))
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(benchmark, "WORKSPACE", Path(directory).absolute()), \
                patch.object(benchmark, "get_conn", return_value=connection), \
                patch.object(benchmark, "psycopg2", adapter), contextlib.redirect_stdout(output):
            benchmark.run_repeated_call_benchmarks()
        progress = [line.strip() for line in output.getvalue().splitlines() if "Replaying derive_child:" in line]
        self.assertEqual(progress, [f"Replaying derive_child: call {i}/8" for i in range(1, 9)])
        self.assertEqual(len(cursor.calls), 9)
        self.assertNotIn("not_for_log", output.getvalue())


class ExpectedJobsTests(unittest.TestCase):
    def test_main_captures_expected_jobs_before_worker_for_setup_and_reuse(self):
        expected = [{"id": 4, "slug": "import_mixed_lu"}]
        for skip in (False, True):
            events = []
            def capture(dataset, skip_setup):
                events.append(("capture", dataset, skip_setup))
                return expected
            def worker(**kwargs):
                events.append(("worker", kwargs["result"]["expected_jobs"]))
                return True
            with self.subTest(skip=skip), patch.object(benchmark, "create_isolated_db"), \
                    patch.object(benchmark, "setup_test_data"), patch.object(benchmark.atexit, "register"), \
                    patch.object(benchmark, "pg_env", return_value={"PGDATABASE": "fixture"}), \
                    patch.object(benchmark, "capture_expected_jobs", side_effect=capture), \
                    patch.object(benchmark, "run_concurrent_test", side_effect=worker), \
                    contextlib.redirect_stdout(io.StringIO()):
                code = benchmark.main(["--dataset", "mixed"] + (["--skip-setup"] if skip else []))
            self.assertEqual(code, 0)
            self.assertEqual(events, [("capture", "mixed", skip), ("worker", expected)])

    def test_preworker_job_selection_matches_dataset_and_optional_source(self):
        class JobsCursor:
            """Before the worker runs, the loader has filled each job's upload table;
            its data table is still empty (analysis fills it)."""
            def __init__(self, slugs):
                self.slugs = slugs
                self.counted = []
            def __enter__(self):
                return self
            def __exit__(self, *args):
                pass
            def execute(self, query):
                self.query = query
                self.counted.append(str(query))
            def fetchall(self):
                columns = {"upload_table_name": "_upload", "data_table_name": "_data"}
                selected = [suffix for name, suffix in columns.items() if name in self.counted[-1]]
                return [(n, slug, *(slug + suffix for suffix in selected)) for n, slug in enumerate(self.slugs, 1)]
            def fetchone(self):
                # Only the upload table holds rows before the worker runs.
                return (10,) if self.counted[-1].endswith("_upload") else (0,)

        mixed = ["import_mixed_seed_lu", "import_mixed_lu", "import_mixed_es", "import_mixed_informal"]
        selection = [f"import_{part}_2026_selection" for part in ("hovedenhet", "underenhet", "roller")]
        downloads = [f"import_{part}_2025" for part in ("hovedenhet", "underenhet", "roller")]
        for dataset, slugs, skip, source, expected in (
                ("mixed", mixed, False, False, mixed[1:]), ("selection", selection, False, False, selection),
                ("downloads", downloads[:2], False, False, downloads[:2]),
                ("downloads", downloads, False, True, downloads),
                ("downloads", downloads, True, False, downloads)):
            conn = Connection(JobsCursor(slugs))
            fake_sql = MagicMock()
            # The counted table is whatever identifier the query names.
            fake_sql.SQL.return_value.format.side_effect = lambda ident: ident
            fake_sql.Identifier.side_effect = lambda name: name
            with self.subTest(dataset=dataset, skip=skip, source=source), \
                    patch.object(benchmark, "get_conn", return_value=conn), \
                    patch.object(benchmark, "sql", fake_sql, create=True), \
                    patch.object(Path, "exists", return_value=source):
                actual = benchmark.capture_expected_jobs(dataset, skip)
            self.assertEqual([row["slug"] for row in actual], expected)
            # uploaded_rows is the loaded input: the upload table's row count.
            self.assertEqual([row["uploaded_rows"] for row in actual], [10] * len(expected))
            self.assertTrue(conn.closed)
        for dataset, slugs, source in (("mixed", mixed[:-1], False),
                                       ("selection", selection[:-1], False),
                                       ("downloads", downloads[:2], True)):
            with self.subTest(missing=dataset), patch.object(benchmark, "get_conn", return_value=Connection(JobsCursor(slugs))), \
                    patch.object(Path, "exists", return_value=source), self.assertRaises(ValueError):
                benchmark.capture_expected_jobs(dataset)
        with patch.object(benchmark, "get_conn", return_value=Connection(JobsCursor(downloads[:2]))), \
                patch.object(Path, "exists", return_value=True), self.assertRaises(ValueError):
            benchmark.capture_expected_jobs("downloads", skip_setup=True)


if __name__ == "__main__":
    unittest.main()
