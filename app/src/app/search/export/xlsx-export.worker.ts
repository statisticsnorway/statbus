/**
 * The dedicated Worker that converts the export's CSV stream into an XLSX
 * workbook (STATBUS-421 S3). Parsing, XML generation and DEFLATE run here so
 * the page stays responsive; the main thread only moves bytes between the
 * network, this Worker and the file.
 *
 * Protocol (one conversion per Worker, requests answered in order):
 *   { type: "init", options }            -> { id, chunks: [] }
 *   { type: "write", id, chunk }         -> { id, chunks }
 *   { type: "end", id }                  -> { id, chunks }
 * A failure answers { id, error: { name, message, code } }; an Excel refusal
 * keeps its name and code so the page can show it as a refusal.
 */

import {
  createLocalXlsxConverter,
  ExcelRefusedError,
  type XlsxChunkConverter,
} from "./xlsx-stream";
import type {
  XlsxWorkerRequest,
  XlsxWorkerResponse,
} from "./xlsx-worker-protocol";
import { ownedChunk } from "./xlsx-worker-protocol";

interface WorkerScope {
  onmessage: ((event: MessageEvent<XlsxWorkerRequest>) => void) | null;
  postMessage(message: XlsxWorkerResponse, transfer: Transferable[]): void;
}

const scope = self as unknown as WorkerScope;
let converter: XlsxChunkConverter | null = null;
// Requests are processed strictly in order, even though each is async.
let queue: Promise<void> = Promise.resolve();

const reply = (id: number, produced: Uint8Array[]) => {
  const chunks = produced.map(ownedChunk);
  scope.postMessage(
    { id, chunks },
    chunks.map((chunk) => chunk.buffer)
  );
};

const fail = (id: number, error: unknown) =>
  scope.postMessage(
    {
      id,
      error: {
        name: error instanceof Error ? error.name : "Error",
        message: error instanceof Error ? error.message : String(error),
        code: error instanceof ExcelRefusedError ? error.code : null,
      },
    },
    []
  );

scope.onmessage = ({ data: request }) => {
  queue = queue.then(async () => {
    try {
      if (request.type === "init") {
        converter = createLocalXlsxConverter(request.options);
        reply(request.id, []);
        return;
      }
      if (!converter) throw new Error("XLSX worker used before init");
      reply(
        request.id,
        request.type === "write"
          ? await converter.write(request.chunk)
          : await converter.end()
      );
    } catch (error) {
      fail(request.id, error);
    }
  });
};
