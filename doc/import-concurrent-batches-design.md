# Concurrent import processing batches

## Execution contract

An import job keeps its existing serial analysis and job ordering. After analysis, the coordinator assigns complete dependency groups to processing batches and spawns concurrent children through `worker.spawn`. The existing worker barrier resumes serial holistic processing and finalization only after every child completes. Different import jobs retain their serial ordering.

`worker.queue_registry` defines the import concurrency default as **4**, matching the existing analytics default. The worker starts four concurrent fibers plus its serial coordinator. Existing per-queue `WORKER_QUEUE_CONCURRENCY` overrides retain their worker-defined precedence. The benchmark records these settings and `WORKER_DEFAULT_CONCURRENCY` rather than silently configuring them. Four is an enabled initial default to measure, not an adaptive sizing claim or proof of safety at every database memory limit.

## Dependency examples

- **Legal-unit updates:** two legal units sharing one enterprise can both change primary selection. Their rows share an enterprise dependency and therefore one batch. For example, changing LU A and LU B under EN X happens in one transaction, while LU C under EN Y can run in another worker.
- **Formal establishments:** histories and siblings sharing one legal-unit parent stay in one batch because primary-establishment selection can update another sibling. Two different legal-unit parents can occupy separate batches.
- **Informal establishments:** the enterprise is their parent and primary-selection dependency, so all its establishments stay in one batch.
- **New identities:** analysis provides a founding row before a persistent parent ID exists. Every era of that identity uses its founding-row dependency.
- **A history crossing assigned parents:** if one founding identity spans more than one assigned batch, the dispatcher keeps the whole job serial. This is a concrete boundary rather than treating every mixed update as unsafe.

Dependency keys map to 16,384 stable hash slots. Whole slots are packed toward the job's existing processing-row target using the cumulative row count before each slot. Hash collisions only combine independent groups. An oversized group stays intact rather than being split to satisfy the target. Analysis retains ordinary row-ID pages. Accepted-row statistics are refreshed once at the analysis-to-processing boundary.

The dispatcher supports the built-in legal-unit, formal-establishment and informal-establishment processing handlers by their typed PostgreSQL routine identities, independently of the caller search path. Custom handlers and single-batch jobs retain serial processing. Legal-relationship and power-group processing are not added to concurrent fanout by this change.

## Transaction and publication timeline

1. A leaf restores the import owner's database context and locks its `(job, batch)` replay identity.
2. Ordered processing handlers write domain rows with ordinary and temporal integrity checks enabled. There is no trigger disable/enable DDL and no SQL Saga prototype dependency.
3. Domain statement triggers immediately append the exact changed IDs and periods to the transactional change log. Within the leaf they record a transaction-local dirty wakeup request instead of taking the shared publication row lock after every statement.
4. The leaf marks its input rows processed and atomically increments `imported_rows` at the transaction tail.
5. The outermost dirty scope publishes the analytics wakeup once. The existing publisher and collector preserve their lock-before-drain correctness contract. Ordinary writes outside this scope still publish immediately.
6. Commit makes domain writes, counters, logged changes and notifications visible together. The UI receives committed progress. Work from an uncommitted batch was not externally visible before this change either.

Nested scopes restore their caller state and propagate dirty requests. A handler failure rolls back its domain changes, processed markers, counters and pending publication together. Deadlocks and serialization errors reaching the worker boundary use its existing bounded retry mechanism. An inner handler may instead translate an error into a failed job. Other leaf failures are recorded by the worker and its after-hook, and fail the job before holistic processing. Already committed sibling batches remain committed, consistent with the existing serial job's per-batch transactions. This does not add an operator replay button or promise whole-job rollback.

## Acceptance evidence and limits

`test/sql/375_statbus_591_concurrent_import_batches.sql` specifies fanout, first-leaf progress, the serial barrier, fan-in, replay, failure propagation and holistic finalization. `380_statbus_591_mixed_and_informal_concurrent_batches.sql` uses genuine analysis results for mixed histories, shared enterprise dependencies, temporal parent coverage and primary selection. A single SQL connection proves the worker protocol, not simultaneous connection behavior.

The additional acceptance path is the literal `test/import_benchmark.sh` wrapper running the actual Crystal worker. `--dataset mixed` queues genuine mixed legal-unit, formal-establishment and informal-establishment histories after fixture preparation. It checks exact business histories, operation counts, parent coverage and primary counts. Existing history consistency and repeated-plan checks remain enabled. `--result-json` records actual queue configuration, per-job analysis and processing times, row errors and durable leaf execution intervals. `--require-import-concurrency 2` is an acceptance assertion, not a configuration override.

The full-file default-four real-worker run and independent read-only correctness results are recorded in the [November 8 validation report](performance/2026-11-concurrent-import-validation.md), including six phase times, row outcomes, actual overlap, graph scope and memory. It does not establish a controlled local-versus-Norway speedup or make the SQL Saga deferral branch necessary.

## Release boundaries

The serial reference is `v2026.11.3-rc.03` at `fc1830fe410b19007056ef0853ad9e491d7f4ad9`. New concurrency migrations follow it rather than modifying released files. The deterministic power-group root proposal is separate. No validity-date default is chosen here. Rabbit owns the separately authorized serial Norway import and recalculation, not experimental concurrency deployment. The owner's overnight instruction is reviewed landing only, with no new RC, tag or release. Personal review remains open.
