/**
 * Start the XLSX conversion Worker (STATBUS-421 S3). Kept apart from the
 * conversion code so that only the browser bundle sees `import.meta.url`;
 * the bundler (Turbopack/webpack) emits xlsx-export.worker.ts as its own
 * module chunk from this exact `new Worker(new URL(...))` form.
 */

import {
  createWorkerXlsxConverter,
  type WorkerLike,
} from "./xlsx-worker-protocol";
import {
  createLocalXlsxConverter,
  type XlsxChunkConverter,
  type XlsxConverterOptions,
} from "./xlsx-stream";

/**
 * A converter running in a dedicated Worker, or in this thread where Workers
 * are unavailable (the output is identical; only responsiveness differs).
 */
export function createXlsxConverter(
  options: XlsxConverterOptions
): XlsxChunkConverter {
  if (typeof Worker === "undefined") return createLocalXlsxConverter(options);
  let worker: Worker;
  try {
    worker = new Worker(new URL("./xlsx-export.worker.ts", import.meta.url), {
      type: "module",
      name: "statbus-xlsx-export",
    });
  } catch {
    return createLocalXlsxConverter(options);
  }
  return createWorkerXlsxConverter(worker as unknown as WorkerLike, options);
}
