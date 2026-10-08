/**
 * Messages between the page and the XLSX Worker (STATBUS-421 S3), plus the
 * page-side client that speaks them. The client implements the same
 * XlsxChunkConverter interface as the in-process converter, so
 * createXlsxSink does not know (or care) that the work happens elsewhere.
 */

import {
  ExcelRefusedError,
  type ExcelRefusalCode,
  type XlsxChunkConverter,
  type XlsxConverterOptions,
} from "./xlsx-stream";

export type XlsxWorkerRequest =
  | { type: "init"; id: number; options: XlsxConverterOptions }
  | { type: "write"; id: number; chunk: Uint8Array }
  | { type: "end"; id: number };

export type XlsxWorkerResponse =
  | { id: number; chunks: Uint8Array[]; error?: undefined }
  | {
      id: number;
      chunks?: undefined;
      error: { name: string; message: string; code: ExcelRefusalCode | null };
    };

/** The minimal Worker surface the client needs (a real Worker satisfies it). */
export interface WorkerLike {
  onmessage: ((event: MessageEvent<XlsxWorkerResponse>) => void) | null;
  onerror: ((event: ErrorEvent) => void) | null;
  postMessage(message: XlsxWorkerRequest, transfer?: Transferable[]): void;
  terminate(): void;
}

/** Rebuild the Worker's error on this side, keeping a refusal a refusal. */
export function workerErrorToError(
  error: NonNullable<XlsxWorkerResponse["error"]>
): Error {
  if (error.name === "ExcelRefusedError" && error.code) {
    return new ExcelRefusedError(error.message, error.code);
  }
  const rebuilt = new Error(error.message);
  rebuilt.name = error.name;
  return rebuilt;
}

/**
 * `chunk` as a view that owns its whole ArrayBuffer, so the buffer can be
 * transferred without detaching bytes that belong to someone else (a view
 * into a larger buffer is copied first).
 */
export function ownedChunk(chunk: Uint8Array): Uint8Array<ArrayBuffer> {
  return chunk.byteOffset === 0 &&
    chunk.byteLength === chunk.buffer.byteLength &&
    chunk.buffer instanceof ArrayBuffer
    ? (chunk as Uint8Array<ArrayBuffer>)
    : chunk.slice();
}

/** An XlsxChunkConverter that runs in `worker`. */
export function createWorkerXlsxConverter(
  worker: WorkerLike,
  options: XlsxConverterOptions
): XlsxChunkConverter {
  let nextId = 0;
  let disposed = false;
  const pending = new Map<
    number,
    { resolve: (chunks: Uint8Array[]) => void; reject: (e: Error) => void }
  >();
  const rejectAll = (error: Error) => {
    for (const { reject } of pending.values()) reject(error);
    pending.clear();
  };
  worker.onmessage = ({ data }) => {
    const request = pending.get(data.id);
    if (!request) return;
    pending.delete(data.id);
    if (data.error) request.reject(workerErrorToError(data.error));
    else request.resolve(data.chunks);
  };
  worker.onerror = (event) => {
    event.preventDefault?.();
    rejectAll(new Error(`XLSX worker failed: ${event.message}`));
  };
  const send = (
    message: XlsxWorkerRequest,
    transfer: Transferable[] = []
  ): Promise<Uint8Array[]> =>
    new Promise((resolve, reject) => {
      if (disposed) {
        reject(new Error("XLSX worker was disposed"));
        return;
      }
      pending.set(message.id, { resolve, reject });
      worker.postMessage(message, transfer);
    });

  const ready = send({ type: "init", id: nextId++, options });
  return {
    async write(chunk) {
      await ready;
      // Transfer, never copy, the bytes to the Worker. The caller has
      // already counted them; the view is detached afterwards.
      const owned = ownedChunk(chunk);
      return send({ type: "write", id: nextId++, chunk: owned }, [
        owned.buffer,
      ]);
    },
    async end() {
      await ready;
      return send({ type: "end", id: nextId++ });
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      worker.terminate();
      rejectAll(new Error("XLSX worker was disposed"));
    },
  };
}
