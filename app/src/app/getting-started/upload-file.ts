/**
 * The getting-started uploads (regions, activity codes, sectors, legal forms) send the file from the
 * browser straight to PostgREST's upload view (7dw69p). A file of any size goes in one request, with
 * no app server in between to impose a body limit: Uganda's 1.8 MB region file was refused by the
 * Next.js server action that used to carry it ("Body exceeded 1 MB limit"), and the person saw only
 * "Oops, Something bad happened". Every failure is now told in the form, with the file's name and
 * size and what the server answered (upload-csv-check.ts explains PostgREST's refusals), and is
 * reported to the server log.
 */
import {
  explainUploadFailure,
  prepareUpload,
  viewColumnsFromOpenApi,
} from "./upload-csv-check";

/** The upload views the getting-started pages store files through. */
export type UploadView =
  | "region_upload"
  | "activity_category_enabled_custom"
  | "sector_custom_only"
  | "legal_form_custom_only";

/** What an upload came to: stored, or the message the form shows. */
export interface UploadState {
  readonly error: string | null;
  readonly success?: boolean;
}

/** How the upload reaches PostgREST: the browser's authenticated fetch and the REST base URL. */
export interface UploadTransport {
  restUrl: string;
  fetch: (url: string, init?: RequestInit) => Promise<Response>;
  /** Reports a failed upload to the server log; never throws. */
  report?: (message: string, context: Record<string, unknown>) => void;
}

/** A file size as people read it: 1.8 MB, 412 KB, 120 bytes. */
export function readableSize(bytes: number): string {
  if (bytes >= 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  if (bytes >= 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${bytes} bytes`;
}

/** PostgREST's code for a statement that ran past the role's statement_timeout. */
const STATEMENT_TIMEOUT = "57014";

/**
 * Sends `file` (CSV, as the form prepared it) to `view` and says what came of it. Nothing is stored
 * unless the whole file is: the upload is one request and one transaction.
 */
export async function uploadFile(
  file: FormDataEntryValue | null | undefined,
  view: UploadView,
  transport: UploadTransport
): Promise<UploadState> {
  const prepared = await prepareUpload(file);
  if (!prepared.ok) return { error: prepared.error };
  const named = file as File;
  const about = `${named.name} (${readableSize(named.size)})`;
  const fail = (error: string, context: Record<string, unknown>) => {
    transport.report?.(`upload to ${view} failed`, {
      view,
      file: named.name,
      bytes: named.size,
      rows: prepared.records.length - 1,
      ...context,
    });
    return { error: `${about} was not stored. ${error}` };
  };

  let response: Response;
  try {
    response = await transport.fetch(`${transport.restUrl}/${view}`, {
      method: "POST",
      headers: { "Content-Type": "text/csv" },
      // The checked text: a UTF-8 byte-order mark is already removed, so it cannot become part of
      // the first column's name.
      body: prepared.text,
    });
  } catch (e) {
    const reason = e instanceof Error ? e.message : String(e);
    return fail(
      `The connection to the server was lost before it answered (${reason}). Nothing was stored; check the network and try again.`,
      { reason }
    );
  }
  if (response.ok) return { error: null, success: true };

  const body = await response.text().catch(() => "");
  if (response.status === 413) {
    return fail(
      "The server refused the file as too large (413). Split it into smaller files and upload them one after another: each file adds to what is stored.",
      { status: 413 }
    );
  }
  let code: string | undefined;
  try {
    code = JSON.parse(body)?.code;
  } catch {
    code = undefined;
  }
  if (code === STATEMENT_TIMEOUT) {
    return fail(
      `Storing ${prepared.records.length - 1} rows took longer than the server allows, so nothing was stored. Split the file into smaller files and upload them one after another: each file adds to what is stored.`,
      { status: response.status, body: body.slice(0, 2000) }
    );
  }
  // The view's columns, to name what IS accepted and which columns a length limit applies to. Best
  // effort: without them the message still names what the file got wrong.
  const columns = await (async () => {
    try {
      const openapi = await transport.fetch(`${transport.restUrl}/`, {
        headers: { Accept: "application/openapi+json" },
      });
      return openapi?.ok
        ? viewColumnsFromOpenApi(await openapi.json(), view)
        : null;
    } catch {
      return null;
    }
  })();
  return fail(
    explainUploadFailure(
      { status: response.status, statusText: response.statusText, body },
      prepared.records,
      columns
    ),
    { status: response.status, body: body.slice(0, 2000) }
  );
}
