/**
 * Plain-language checks and error explanations for the getting-started CSV
 * uploads (STATBUS-470).
 *
 * Those steps POST the raw CSV straight to PostgREST (`/<upload view>`). When
 * the file is wrong, PostgREST answers in its own vocabulary: "Could not find
 * the 'X' column of 'v' in the schema cache", "value too long for type
 * character varying(512)", "parse error (not enough input)". This module
 * turns that into a message an operator can act on without guessing: which
 * columns are wrong and which are accepted, which row and column is too long
 * and what the limit is, or simply that the file is empty.
 */

/** One CSV record with the file line it starts on (1-based). */
export interface CsvRecord {
  fields: string[];
  line: number;
}

/**
 * RFC 4180 parsing: quoted fields, "" escapes, embedded newlines, CRLF.
 * Records are returned with the line each one starts on, so a message can
 * point at the line an editor shows.
 */
export function parseCsvRecords(text: string): CsvRecord[] {
  const records: CsvRecord[] = [];
  let fields: string[] = [];
  let field = "";
  let inQuotes = false;
  let line = 1;
  let recordLine = 1;
  let recordHasContent = false;
  const endRecord = () => {
    fields.push(field);
    if (recordHasContent || fields.length > 1 || field !== "") {
      records.push({ fields, line: recordLine });
    }
    fields = [];
    field = "";
    recordHasContent = false;
  };
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i++;
        } else inQuotes = false;
      } else {
        if (c === "\n") line++;
        field += c;
      }
      continue;
    }
    if (c === '"') {
      inQuotes = true;
      recordHasContent = true;
    } else if (c === ",") {
      fields.push(field);
      field = "";
      recordHasContent = true;
    } else if (c === "\n") {
      endRecord();
      line++;
      recordLine = line;
    } else if (c === "\r") {
      // part of CRLF; the \n ends the record
    } else {
      field += c;
      recordHasContent = true;
    }
  }
  if (recordHasContent || field !== "" || fields.length > 0) endRecord();
  return records;
}

/** The file as it will be sent, or the message saying why it cannot be. */
export type PreparedUpload =
  | { ok: true; text: string; records: CsvRecord[] }
  | { ok: false; error: string };

/**
 * Check the file before anything is sent: present, not empty, has data rows.
 * Strips a UTF-8 byte-order mark (Excel's "CSV UTF-8" writes one), which
 * would otherwise become part of the first column's name.
 */
export async function prepareUpload(
  file: FormDataEntryValue | null | undefined
): Promise<PreparedUpload> {
  // A form with no file chosen sends either nothing or an empty, nameless
  // File (what browsers submit for an empty <input type="file">).
  if (!file || typeof file === "string" || (file.size === 0 && !file.name)) {
    return {
      ok: false,
      error: "No file selected. Choose a CSV file, then press Upload.",
    };
  }
  if (file.size === 0) {
    return { ok: false, error: `The file ${file.name} is empty.` };
  }
  const text = (await file.text()).replace(/^\uFEFF/, "");
  const records = parseCsvRecords(text);
  if (records.length === 0) {
    return { ok: false, error: `The file ${file.name} is empty.` };
  }
  if (records.length === 1) {
    return {
      ok: false,
      error: `The file ${file.name} has a header row but no data rows.`,
    };
  }
  return { ok: true, text, records };
}

/** A view's columns as PostgREST's OpenAPI document describes them. */
export interface ViewColumn {
  name: string;
  maxLength?: number;
}

/** What PostgREST answered for a rejected upload. */
export interface UploadFailure {
  status: number;
  statusText: string;
  /** The raw response body. */
  body: string;
}

const characters = (value: string) => [...value].length;

function list(values: string[]): string {
  return values.join(", ");
}

/** The separator a header seems to use instead of a comma, if any. */
function otherSeparator(header: string[]): string | null {
  if (header.length !== 1) return null;
  if (header[0].includes(";")) return "semicolons (;)";
  if (header[0].includes("\t")) return "tabs";
  return null;
}

/**
 * The plain message for a rejected upload. `records` is the parsed file
 * (header first); `columns` is the view's column list when it could be read
 * (needed to say what IS accepted, and to tell which columns a length limit
 * applies to).
 */
export function explainUploadFailure(
  failure: UploadFailure,
  records: CsvRecord[],
  columns: ViewColumn[] | null
): string {
  let parsed: {
    code?: string;
    message?: string;
    details?: string | null;
    hint?: string | null;
  } | null = null;
  try {
    parsed = JSON.parse(failure.body);
  } catch {
    parsed = null;
  }
  if (!parsed || typeof parsed.message !== "string") {
    const body = failure.body.trim().slice(0, 300);
    const status = [failure.status, failure.statusText]
      .filter((part) => part !== "")
      .join(" ");
    return `The server answered ${status}${body ? `: ${body}` : ""}`;
  }
  const header = records[0]?.fields ?? [];
  const rows = records.slice(1);

  // PGRST204: a file column the view does not have. PostgREST names only the
  // first one; name them all, and what the view accepts.
  if (parsed.code === "PGRST204") {
    const separator = otherSeparator(header);
    if (separator) {
      return `The file uses ${separator} between columns. Save it as a comma-separated CSV and upload it again.`;
    }
    if (columns && columns.length > 0) {
      const accepted = columns.map((column) => column.name);
      const unknown = header.filter((name) => !accepted.includes(name));
      const caseHints = unknown
        .map((name) => {
          const match = accepted.find(
            (a) => a.toLowerCase() === name.trim().toLowerCase()
          );
          return match ? `${name} could be ${match}` : null;
        })
        .filter((hint): hint is string => hint !== null);
      return (
        `The file has columns this step does not accept: ${list(unknown)}. ` +
        `The accepted columns are: ${list(accepted)}.` +
        (caseHints.length
          ? ` Column names are case-sensitive (${list(caseHints)}).`
          : "")
      );
    }
    const column = /Could not find the '(.*)' column/.exec(parsed.message);
    return `The file has a column this step does not accept: ${column ? column[1] : parsed.message}.`;
  }

  // 22001: a value longer than a varchar(n) column. Find the cell(s).
  if (parsed.code === "22001") {
    const limitMatch = /character varying\((\d+)\)/.exec(parsed.message);
    const limit = limitMatch ? Number(limitMatch[1]) : null;
    if (limit != null) {
      const limited = columns
        ? new Set(
            columns
              .filter((column) => column.maxLength === limit)
              .map((column) => column.name)
          )
        : null;
      const offenders: string[] = [];
      rows.forEach((record, index) => {
        record.fields.forEach((value, column) => {
          const name = header[column] ?? `column ${column + 1}`;
          if (limited && limited.size > 0 && !limited.has(name)) return;
          const length = characters(value);
          if (length > limit) {
            offenders.push(
              `row ${index + 1} (line ${record.line}), column ${name}: ${length} characters`
            );
          }
        });
      });
      if (offenders.length > 0) {
        const more =
          offenders.length > 1
            ? ` (and ${offenders.length - 1} more value${offenders.length > 2 ? "s" : ""} over the limit)`
            : "";
        return `A value is longer than the column allows (${limit} characters): ${offenders[0]}${more}.`;
      }
      return `A value is longer than the column allows (${limit} characters).`;
    }
  }

  // 23502: a required column has no value.
  if (parsed.code === "23502") {
    const column = /null value in column "([^"]+)"/.exec(parsed.message)?.[1];
    if (column) {
      const index = header.indexOf(column);
      if (index < 0) {
        return `The file has no ${column} column, which is required.`;
      }
      const empty = rows.findIndex((record) => !record.fields[index]);
      if (empty >= 0) {
        return `Row ${empty + 1} (line ${rows[empty].line}) has no value in column ${column}, which is required.`;
      }
      return `Column ${column} is required and a row has no value for it.`;
    }
  }

  // Anything else: PostgREST's own words, with its details and hint.
  return [parsed.message, parsed.details, parsed.hint]
    .filter((part): part is string => typeof part === "string" && part !== "")
    .join(" ");
}

/** The view's columns from a PostgREST OpenAPI document, or null. */
export function viewColumnsFromOpenApi(
  openapi: unknown,
  view: string
): ViewColumn[] | null {
  const definitions = (
    openapi as {
      definitions?: Record<
        string,
        { properties?: Record<string, { maxLength?: number }> }
      >;
    } | null
  )?.definitions;
  const properties = definitions?.[view]?.properties;
  if (!properties) return null;
  return Object.entries(properties).map(([name, property]) => ({
    name,
    maxLength:
      typeof property.maxLength === "number" ? property.maxLength : undefined,
  }));
}
