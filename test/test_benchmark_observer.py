#!/usr/bin/env python3
"""Offline observer tests: python3 -m unittest discover -s test -p 'test_benchmark_observer.py'."""
import contextlib
from datetime import datetime, timedelta, timezone
from decimal import Decimal
import importlib.util
import io
import json
import logging
import os
from types import SimpleNamespace
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("import_benchmark", os.environ.get(
    "BENCHMARK_MODULE_PATH", Path(__file__).with_name("import_benchmark.py")))
benchmark = importlib.util.module_from_spec(SPEC)
with patch("logging.FileHandler", return_value=logging.NullHandler()):
    SPEC.loader.exec_module(benchmark)
BASE = datetime(2026, 11, 8, tzinfo=timezone.utc)


def at(seconds):
    return BASE + timedelta(seconds=seconds)


def leaf(job_id, start, stop):
    return {"job_id": job_id, "process_start_at": at(start), "process_stop_at": at(stop)}


class IntervalTests(unittest.TestCase):
    def test_overlapping_intervals_measure_actual_peak_and_time(self):
        result = benchmark.interval_summary([(at(3), at(6)), (at(0), at(5)), (at(2), at(4))])
        self.assertEqual(result["max_concurrent_processing_leaves"], 3)
        self.assertEqual(result["overlap_seconds"], 3)
        self.assertEqual(result["seconds_by_concurrency"], {"1": 3, "2": 2, "3": 1})
        self.assertEqual(result["span_seconds"], 6)
        self.assertEqual(result["complete_intervals"], 3)

    def test_touching_endpoints_and_zero_duration(self):
        result = benchmark.interval_summary([(at(0), at(1)), (at(1), at(2)), (at(1), at(1))])
        self.assertEqual(result["max_concurrent_processing_leaves"], 1)
        self.assertEqual(result["seconds_by_concurrency"], {"1": 2})
        self.assertEqual(result["overlap_seconds"], 0)
        self.assertEqual(result["complete_intervals"], 3)

    def test_gaps_and_identical_intervals(self):
        result = benchmark.interval_summary([(at(0), at(1)), (at(3), at(4)), (at(3), at(4))])
        self.assertEqual(result["seconds_by_concurrency"], {"0": 2, "1": 1, "2": 1})
        self.assertEqual(result["max_concurrent_processing_leaves"], 2)

    def test_incomplete_intervals_are_explicit_not_inferred(self):
        result = benchmark.interval_summary([(None, at(1)), (at(0), None)])
        self.assertEqual(result["incomplete_intervals"], 2)
        self.assertEqual(result["max_concurrent_processing_leaves"], 0)
        self.assertEqual(result["span_seconds"], 0)
        self.assertEqual(benchmark.interval_summary([])["complete_intervals"], 0)

    def test_reversed_interval_is_an_error(self):
        with self.assertRaisesRegex(ValueError, "precedes"):
            benchmark.interval_summary([(at(2), at(1))])

    def test_job_identity_and_phase_chronology(self):
        jobs = [{"id": n, "slug": f"job-{n}", "analysis_start_at": at(n * 10),
                 "analysis_stop_at": at(n * 10 + 2), "processing_start_at": at(n * 10 + 3),
                 "processing_stop_at": at(n * 10 + 7), "imported_rows": n * 100}
                for n in (1, 2)]
        leaves = [leaf("1", 13, 16), leaf("2", 23, 25), leaf(1, 14, 17)]
        first, second = benchmark.summarize_jobs(jobs, leaves)
        self.assertEqual(first["processing_overlap"]["max_concurrent_processing_leaves"], 2)
        self.assertEqual(second["processing_overlap"]["max_concurrent_processing_leaves"], 1)
        self.assertEqual(first["analysis"], {"start_at": at(10), "stop_at": at(12), "duration_seconds": 2})
        self.assertEqual(second["processing"], {"start_at": at(23), "stop_at": at(27), "duration_seconds": 4})
        self.assertEqual([len(first["processing_leaves"]), len(second["processing_leaves"])], [2, 1])
        self.assertEqual(second["imported_rows"], 200)
        self.assertLess(first["processing"]["stop_at"], second["analysis"]["start_at"])

    def test_incomplete_and_invalid_phase_timing(self):
        job = {"id": 1, "analysis_start_at": at(1), "analysis_stop_at": None}
        self.assertIsNone(benchmark.phase_summary(job, "analysis")["duration_seconds"])
        job["analysis_stop_at"] = at(0)
        with self.assertRaisesRegex(ValueError, "Job 1 analysis"):
            benchmark.phase_summary(job, "analysis")


class ReportingTests(unittest.TestCase):
    def test_json_round_trip_preserves_actual_values(self):
        result = {"success": False, "worker": {"start_at": BASE, "wall_seconds": 2.5},
                  "failed_task_count": 12, "duration_ms": Decimal("1.25"),
                  "jobs": [{"id": 4, "actual_data_rows": {"total": 8, "processed": 7, "error": 1}}],
                  "processing_overlap": benchmark.interval_summary([(at(0), at(2)), (at(1), at(3))])}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "nested" / "result.json"
            benchmark.write_result(path, result)
            loaded = json.loads(path.read_text())
            self.assertEqual(loaded["worker"]["start_at"], BASE.isoformat())
            self.assertEqual(loaded["duration_ms"], 1.25)
            self.assertEqual(loaded["failed_task_count"], 12)
            self.assertEqual(loaded["jobs"][0]["actual_data_rows"], {"total": 8, "processed": 7, "error": 1})
            self.assertEqual(loaded["processing_overlap"]["max_concurrent_processing_leaves"], 2)
            self.assertEqual(list(path.parent.iterdir()), [path])

    def test_acceptance_compares_durable_peak_without_changing_it(self):
        observation = benchmark.interval_summary([(at(0), at(1))])
        for minimum, passed in ((None, True), (1, True), (2, False)):
            with self.subTest(minimum=minimum):
                result = benchmark.concurrency_acceptance(observation, minimum)
                self.assertEqual(result, {"required_minimum": minimum, "observed_actual": 1,
                                          "passed": passed, "evidence": "durable_process_intervals"})
        self.assertEqual(observation["max_concurrent_processing_leaves"], 1)

    def test_serial_default_and_valid_options(self):
        args = benchmark.parse_args([])
        self.assertIsNone(args.require_import_concurrency)
        args = benchmark.parse_args(["--result-json", "result.json", "--require-import-concurrency", "3"])
        self.assertEqual(args.result_json, Path("result.json"))
        self.assertEqual(args.require_import_concurrency, 3)

    def test_invalid_options_exit_before_database_access(self):
        for options in (["--require-import-concurrency", "0"], ["--require-import-concurrency", "-1"],
                        ["--require-import-concurrency", "1.5"], ["--require-import-concurrency", "bad"],
                        ["--list", "--require-import-concurrency", "2"],
                        ["--timing", "unused", "--result-json", "unused"]):
            with self.subTest(options=options), contextlib.redirect_stderr(io.StringIO()), \
                    patch.object(benchmark, "get_conn") as connection:
                with self.assertRaises(SystemExit) as error:
                    benchmark.main(options)
                self.assertEqual(error.exception.code, 2)
                connection.assert_not_called()

    def test_setup_error_is_a_failed_json_result(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "result.json"
            with patch.object(benchmark, "create_isolated_db", side_effect=RuntimeError("setup unavailable")), \
                    contextlib.redirect_stdout(io.StringIO()):
                code = benchmark.main(["--result-json", str(path)])
            self.assertEqual(code, 1)
            result = json.loads(path.read_text())
            self.assertFalse(result["success"])
            self.assertEqual(result["error"], {"type": "RuntimeError", "message": "setup unavailable"})

    def test_worker_timeout_retains_exit_and_timeout_evidence(self):
        class Process:
            stdout = iter([])
            returncode = 0
            waits = 0
            terminated = False

            def wait(self, timeout=None):
                self.waits += 1
                if self.waits == 1:
                    raise subprocess.TimeoutExpired("worker", timeout)
                return self.returncode

            def terminate(self):
                self.terminated = True

        process = Process()
        with patch.object(benchmark.Path, "exists", return_value=True), \
                patch.object(benchmark.subprocess, "Popen", return_value=process), \
                contextlib.redirect_stdout(io.StringIO()):
            code, output, elapsed = benchmark.run_worker("offline-unused", timeout_seconds=1, debug=False)
        self.assertEqual(code, 0)
        self.assertEqual(output, [])
        self.assertGreaterEqual(elapsed, 0)
        self.assertTrue(process.terminated)
        self.assertTrue(benchmark.LAST_WORKER_RUN["timed_out"])
        self.assertEqual(benchmark.LAST_WORKER_RUN["returncode"], 0)
        self.assertGreaterEqual(benchmark.LAST_WORKER_RUN["stop_at"], benchmark.LAST_WORKER_RUN["start_at"])

    def test_full_benchmark_preserves_checks_and_enforces_acceptance(self):
        class Cursor:
            def __enter__(self):
                self.results = iter([[('completed', 2)], [], []])
                return self

            def __exit__(self, *args):
                pass

            def execute(self, *args):
                pass

            def fetchall(self):
                return next(self.results)

        class Connection:
            def cursor(self):
                return Cursor()

            def close(self):
                pass

        observation = {"failed_task_count": 0,
                       "processing_overlap": benchmark.interval_summary([(at(0), at(1))])}
        for minimum, timed_out, returncode, dataset_passed, expected in (
                (None, False, 0, True, True), (1, False, 0, True, True), (2, False, 0, True, False),
                (None, True, 0, True, False), (None, False, 1, True, False),
                (None, False, 0, False, False)):
            with self.subTest(minimum=minimum, timed_out=timed_out, returncode=returncode), \
                    patch.object(benchmark, "run_worker", return_value=(returncode, [], 1)), \
                    patch.object(benchmark, "LAST_WORKER_RUN", {"timed_out": timed_out}), \
                    patch.object(benchmark, "collect_observation", return_value=observation), \
                    patch.object(benchmark, "get_conn", return_value=Connection()), \
                    patch.object(benchmark, "check_dataset", return_value={
                        "status": "passed" if dataset_passed else "failed", "passed": dataset_passed}) as dataset_check, \
                    patch.object(benchmark, "check_consistency", return_value=(True, "A/B/C passed")) as consistency, \
                    patch.object(benchmark, "run_hierarchy_benchmarks") as hierarchy, \
                    patch.object(benchmark, "run_repeated_call_benchmarks", return_value=True) as plans, \
                    contextlib.redirect_stdout(io.StringIO()):
                result = {}
                success = benchmark.run_concurrent_test(result=result, require_import_concurrency=minimum)
                self.assertEqual(success, expected)
                self.assertEqual(result["success"], expected)
                self.assertEqual(result["checks"]["consistency"], {"passed": True, "summary": "A/B/C passed"})
                self.assertEqual(result["checks"]["dataset"]["passed"], dataset_passed)
                dataset_check.assert_called_once_with("selection")
                consistency.assert_called_once_with()
                hierarchy.assert_called_once_with()
                plans.assert_called_once_with()


class MixedAdapterTests(unittest.TestCase):
    def test_mixed_options_and_sql_fixture_adapter(self):
        args = benchmark.parse_args(["--dataset", "mixed", "--result-json", "mixed.json",
                                     "--require-import-concurrency", "2"])
        self.assertEqual((args.dataset, args.require_import_concurrency), ("mixed", 2))
        with patch.object(benchmark, "run_psql_file", return_value="fixture queued") as sql_file, \
                patch.object(benchmark.subprocess, "run") as loader:
            benchmark.setup_test_data("mixed")
        sql_file.assert_called_once_with("test/import_benchmark_mixed.sql")
        loader.assert_not_called()

    def test_measured_jobs_and_overlap_use_only_actual_mixed_imports(self):
        jobs = [{"id": n, "slug": slug} for n, slug in enumerate(
            ("import_mixed_seed_lu", "import_mixed_lu", "import_mixed_es", "import_mixed_informal"))]
        leaves = [leaf("0", 0, 10), leaf(0, 0, 10), leaf("1", 20, 22),
                  leaf(2, 21, 23), leaf(3, 24, 25)]
        measured_jobs, measured_leaves = benchmark.measured_imports("mixed", jobs, leaves)
        self.assertEqual([job["slug"] for job in measured_jobs],
                         ["import_mixed_lu", "import_mixed_es", "import_mixed_informal"])
        self.assertEqual(measured_leaves, leaves[2:])
        overlap = benchmark.interval_summary((row["process_start_at"], row["process_stop_at"])
                                             for row in measured_leaves)
        self.assertEqual(overlap["complete_intervals"], 3)
        self.assertEqual(overlap["overlap_seconds"], 1)
        for dataset in ("selection", "downloads"):
            self.assertEqual(benchmark.measured_imports(dataset, jobs, leaves), (jobs, leaves))

    def test_dataset_sql_success_and_failure_are_json_evidence(self):
        for error, status, passed in ((None, "passed", True), (RuntimeError("wrong histories"), "failed", False)):
            with self.subTest(status=status), patch.object(benchmark, "run_psql_file", \
                    return_value="Exact histories passed", side_effect=error) as sql_file:
                result = benchmark.check_dataset("mixed")
            sql_file.assert_called_once_with("test/import_benchmark_mixed_check.sql")
            self.assertEqual((result["status"], result["passed"]), (status, passed))
            self.assertEqual(json.loads(json.dumps(result)), result)
        with patch.object(benchmark, "run_psql_file") as sql_file:
            self.assertEqual(benchmark.check_dataset("selection"),
                             {"status": "not_applicable", "passed": True})
            sql_file.assert_not_called()

    def test_main_forwards_mixed_to_real_worker_gate_and_writes_check(self):
        def run(**kwargs):
            self.assertEqual(kwargs["dataset"], "mixed")
            self.assertEqual(kwargs["require_import_concurrency"], 2)
            kwargs["result"]["checks"] = {"dataset": {"status": "passed", "passed": True}}
            kwargs["result"]["success"] = True
            return True

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "mixed.json"
            with patch.object(benchmark, "create_isolated_db"), \
                    patch.object(benchmark, "setup_test_data") as setup, \
                    patch.object(benchmark.atexit, "register"), \
                    patch.object(benchmark, "run_concurrent_test", side_effect=run), \
                    contextlib.redirect_stdout(io.StringIO()):
                code = benchmark.main(["--dataset", "mixed", "--result-json", str(path),
                                       "--require-import-concurrency", "2"])
            self.assertEqual(code, 0)
            setup.assert_called_once_with("mixed")
            self.assertEqual(json.loads(path.read_text())["checks"]["dataset"]["status"], "passed")


class DateAdapterTests(unittest.TestCase):
    def test_explicit_calendar_dates_and_year_boundaries(self):
        for value in ("0001-01-01", "2000-02-29", "2024-02-29", "9999-12-31"):
            with self.subTest(value=value):
                self.assertEqual(benchmark.parse_args(["--valid-from", value]).valid_from, value)
        for supplied, expected in (("1", "0001"), ("0001", "0001"), ("2024", "2024"), ("9999", "9999")):
            with self.subTest(year=supplied):
                self.assertEqual(benchmark.parse_args(["--year", supplied]).year, expected)

    def test_invalid_or_inapplicable_dates_fail_before_database_or_loader(self):
        options = [["--valid-from", value] for value in
                   ("0000-01-01", "10000-01-01", "1900-02-29", "2023-02-29", "2024-04-31",
                    "2024-00-01", "2024-01-00", "2024-1-01", "20240101", "2024-01-01T00:00:00")]
        options += [["--year", value] for value in ("0", "10000", "-1", "1.5", "no", " 2024", "２０２４")]
        options += [["--valid-from", "2024-01-01", "--year", "2024"]]
        for date_option in (["--year", "2024"], ["--valid-from", "2024-02-29"]):
            for action in (["--dataset", "mixed"], ["--skip-setup"], ["--list"], ["--cleanup-all"],
                           ["--timing", "unused"], ["--repeated-calls", "unused"]):
                options.append(date_option + action)
        for argv in options:
            with self.subTest(argv=argv), contextlib.redirect_stderr(io.StringIO()), \
                    patch.object(benchmark, "create_isolated_db") as create, \
                    patch.object(benchmark, "get_conn") as connect, \
                    patch.object(benchmark.subprocess, "run") as subprocess_run:
                with self.assertRaises(SystemExit) as error:
                    benchmark.main(argv)
                self.assertEqual(error.exception.code, 2)
                create.assert_not_called()
                connect.assert_not_called()
                subprocess_run.assert_not_called()

    def test_loader_receives_database_and_validity_with_legacy_defaults_unchanged(self):
        for dataset in ("selection", "downloads"):
            for validity, expected in (({}, []), ({"valid_from": "2024-02-29"}, ["--valid-from", "2024-02-29"]),
                                       ({"year": "0001"}, ["--year", "0001"])):
                with self.subTest(dataset=dataset, validity=validity), \
                        patch.object(benchmark, "TEST_DB", "private_test"), \
                        patch.object(benchmark.Path, "exists", return_value=True), \
                        patch.object(benchmark.Path, "stat", return_value=SimpleNamespace(st_size=27)), \
                        patch.object(benchmark, "run_psql_file"), \
                        patch.object(benchmark, "get_conn"), \
                        patch.object(benchmark.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout="")) as run, \
                        contextlib.redirect_stdout(io.StringIO()):
                    benchmark.setup_test_data(dataset, **validity)
                self.assertEqual(run.call_args.args[0],
                                 [str(benchmark.WORKSPACE / benchmark.DATASETS[dataset]["loader"]),
                                  "--database", "private_test"] + expected)

    def test_all_three_download_sources_have_exact_mocked_byte_hash_metadata(self):
        sources = ["tmp/enheter.csv", "tmp/underenheter_filtered.csv", "tmp/roller_legal_relationships.csv"]
        payloads = {str(benchmark.WORKSPACE / path): data for path, data in zip(sources, (b"lu\n", b"es\n", b"roller\n"))}
        import hashlib

        def opened(path, *args, **kwargs):
            return io.BytesIO(payloads[str(path)])

        def stated(path, *args, **kwargs):
            return SimpleNamespace(st_size=len(payloads[str(path)]))

        with patch.object(Path, "exists", return_value=True), \
                patch.object(Path, "open", opened), patch.object(Path, "stat", stated):
            metadata = benchmark.source_metadata("downloads")
        self.assertEqual(metadata, [{"path": path, "present": True, "size_bytes": len(payloads[str(benchmark.WORKSPACE / path)]),
                                     "sha256": hashlib.sha256(payloads[str(benchmark.WORKSPACE / path)]).hexdigest()}
                                    for path in sources])
        with patch.object(Path, "exists", side_effect=lambda: False), \
                patch.object(Path, "open", opened), patch.object(Path, "stat", stated):
            metadata = benchmark.source_metadata("downloads")
        self.assertEqual(metadata[-1], {"path": sources[-1], "present": False, "size_bytes": None, "sha256": None})

    def test_observer_records_actual_default_valid_from_for_all_three_jobs(self):
        slugs = ("import_hovedenhet_2024_selection", "import_underenhet_2024_selection", "import_roller_2024_selection")
        dates = (benchmark.date(2024, 1, 1), benchmark.date(2024, 2, 29), benchmark.date(2024, 12, 31))

        class Cursor:
            def __enter__(self):
                return self

            def __exit__(self, *args):
                pass

            def execute(self, query, *args):
                self.query = str(query)

            def fetchall(self):
                if "FROM public.import_job ORDER BY id" not in self.query:
                    return []
                jobs = []
                for n, (slug, valid_from) in enumerate(zip(slugs, dates)):
                    job = {"id": n, "slug": slug, "data_table_name": slug + "_data",
                           "analysis_start_at": None, "analysis_stop_at": None,
                           "processing_start_at": None, "processing_stop_at": None}
                    if "default_valid_from" in self.query:
                        job["default_valid_from"] = valid_from
                    jobs.append(job)
                return jobs

            def fetchone(self):
                return {"start_at": None, "stop_at": None, "span_seconds": None}

        from unittest.mock import MagicMock
        connection = MagicMock()
        connection.cursor.return_value = Cursor()
        with patch.object(benchmark, "get_conn", return_value=connection), \
                patch.object(benchmark, "psycopg2", MagicMock()), \
                patch.object(benchmark, "sql", MagicMock(), create=True):
            result = benchmark.collect_observation()
        self.assertEqual([(job["slug"], job["default_valid_from"]) for job in result["jobs"]], list(zip(slugs, dates)))
        encoded = json.loads(json.dumps(result, default=benchmark.json_value))
        self.assertEqual([job["default_valid_from"] for job in encoded["jobs"]], [value.isoformat() for value in dates])
        connection.close.assert_called_once_with()

    def test_main_forwards_explicit_date_and_records_mocked_source_metadata(self):
        metadata = [{"path": path, "sha256": str(n) * 64, "size_bytes": n, "present": True}
                    for n, path in enumerate(("tmp/enheter.csv", "tmp/underenheter_filtered.csv", "tmp/roller_legal_relationships.csv"), 1)]
        for date_args, expected in ((["--valid-from", "2024-02-29"], {"valid_from": "2024-02-29", "year": None}),
                                    (["--year", "1"], {"valid_from": None, "year": "0001"})):
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "result.json"
                with patch.object(benchmark, "create_isolated_db"), patch.object(benchmark.atexit, "register"), \
                        patch.object(benchmark, "setup_test_data") as setup, \
                        patch.object(benchmark, "source_metadata", return_value=metadata) as source, \
                        patch.object(benchmark, "run_concurrent_test", return_value=True), \
                        contextlib.redirect_stdout(io.StringIO()):
                    code = benchmark.main(["--dataset", "downloads", "--result-json", str(path)] + date_args)
                self.assertEqual(code, 0)
                setup.assert_called_once_with("downloads", **expected)
                source.assert_called_once_with("downloads")
                recorded = json.loads(path.read_text())
                self.assertEqual(recorded["source_files"], metadata)
                self.assertEqual(recorded["requested_validity"], expected)


class LoaderTimingTests(unittest.TestCase):
    def test_actual_loader_interval_is_utc_and_serialized_on_success_and_failure(self):
        for fails in (False, True):
            start, stop = at(30), at(34)
            clock_values = iter((start, stop))
            events = []

            class Clock(datetime):
                @classmethod
                def now(cls, tz=None):
                    self.assertEqual(tz, timezone.utc)
                    return next(clock_values)

            def setup_sql(path):
                self.assertEqual(path, "test/setup.sql")
                self.assertEqual(getattr(benchmark, "LAST_LOAD_RUN", {}), {})
                events.append("setup_sql")

            def loader(argv, **kwargs):
                self.assertEqual(benchmark.LAST_LOAD_RUN, {"start_at": start})
                self.assertEqual(argv[-2:], ["--valid-from", "2024-02-29"])
                events.append("loader")
                if fails:
                    raise RuntimeError("loader unavailable")
                return SimpleNamespace(returncode=0, stdout="")

            with self.subTest(fails=fails), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "result.json"
                with patch.object(benchmark, "datetime", Clock), \
                        patch.object(benchmark, "create_isolated_db"), patch.object(benchmark.atexit, "register"), \
                        patch.object(benchmark, "source_metadata", return_value=[]), \
                        patch.object(benchmark.Path, "exists", return_value=True), \
                        patch.object(benchmark.Path, "stat", return_value=SimpleNamespace(st_size=27, st_mode=0o040755)), \
                        patch.object(benchmark, "run_psql_file", side_effect=setup_sql), \
                        patch.object(benchmark, "get_conn"), \
                        patch.object(benchmark.subprocess, "run", side_effect=loader), \
                        patch.object(benchmark, "run_concurrent_test", return_value=True) as worker, \
                        contextlib.redirect_stdout(io.StringIO()):
                    code = benchmark.main(["--dataset", "selection", "--valid-from", "2024-02-29",
                                           "--result-json", str(path)])
                self.assertEqual(code, 1 if fails else 0)
                self.assertEqual(events, ["setup_sql", "loader"])
                recorded = json.loads(path.read_text())
                self.assertEqual(recorded["load"], {"start_at": start.isoformat(), "stop_at": stop.isoformat()})
                if fails:
                    worker.assert_not_called()
                else:
                    worker.assert_called_once()

    def test_skip_setup_omits_load_evidence_even_after_a_previous_run(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "result.json"
            with patch.object(benchmark, "LAST_LOAD_RUN", {"start_at": at(1), "stop_at": at(2)}, create=True), \
                    patch.object(benchmark, "pg_env", return_value={"PGDATABASE": "already_loaded"}), \
                    patch.object(benchmark, "setup_test_data") as setup, \
                    patch.object(benchmark, "source_metadata") as metadata, \
                    patch.object(benchmark, "run_concurrent_test", return_value=True), \
                    contextlib.redirect_stdout(io.StringIO()):
                code = benchmark.main(["--skip-setup", "--result-json", str(path)])
            self.assertEqual(code, 0)
            self.assertNotIn("load", json.loads(path.read_text()))
            setup.assert_not_called()
            metadata.assert_not_called()


if __name__ == "__main__":
    unittest.main()
