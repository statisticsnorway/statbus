#!/usr/bin/env python3
"""Offline observer tests: python3 -m unittest discover -s test -p 'test_benchmark_observer.py'."""
import contextlib
from datetime import datetime, timedelta, timezone
from decimal import Decimal
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("import_benchmark", Path(__file__).with_name("import_benchmark.py"))
benchmark = importlib.util.module_from_spec(SPEC)
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
        for minimum, timed_out, returncode, expected in (
                (None, False, 0, True), (1, False, 0, True), (2, False, 0, False),
                (None, True, 0, False), (None, False, 1, False)):
            with self.subTest(minimum=minimum, timed_out=timed_out, returncode=returncode), \
                    patch.object(benchmark, "run_worker", return_value=(returncode, [], 1)), \
                    patch.object(benchmark, "LAST_WORKER_RUN", {"timed_out": timed_out}), \
                    patch.object(benchmark, "collect_observation", return_value=observation), \
                    patch.object(benchmark, "get_conn", return_value=Connection()), \
                    patch.object(benchmark, "check_consistency", return_value=(True, "A/B/C passed")) as consistency, \
                    patch.object(benchmark, "run_hierarchy_benchmarks") as hierarchy, \
                    patch.object(benchmark, "run_repeated_call_benchmarks", return_value=True) as plans, \
                    contextlib.redirect_stdout(io.StringIO()):
                result = {}
                success = benchmark.run_concurrent_test(result=result, require_import_concurrency=minimum)
                self.assertEqual(success, expected)
                self.assertEqual(result["success"], expected)
                self.assertEqual(result["checks"]["consistency"], {"passed": True, "summary": "A/B/C passed"})
                consistency.assert_called_once_with()
                hierarchy.assert_called_once_with()
                plans.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
