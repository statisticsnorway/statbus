/**
 * The encoding check of an import upload (e1z8va): an uploaded file is UTF-8
 * text, and text that was once UTF-8 read as Windows-1252 is refused too,
 * during the upload, so the file never reaches the import step. On 2026-11-13
 * two Norway imports stored 454,278 legal unit rows with Ø, Å and Æ as two
 * garbled characters ("RÃ˜RSERVICE"): nothing checked the file. The user fixes
 * the file and uploads it again; nothing is guessed or converted here.
 *
 * The upload route pushes each chunk of the file as it streams to the
 * database, then calls end(); the first problem throws UploadEncodingError,
 * naming the line and the value. Lines are counted by newlines, so a quoted
 * value that spans lines counts each.
 */

const SAVE_AS_UTF8 =
  'Save the file as UTF-8 and upload it again (in Excel: Save As, "CSV UTF-8 (Comma delimited)"; ' +
  'in LibreOffice: Save As, Character set "Unicode (UTF-8)").';

/** Why an upload was refused; its message is shown to the user as is. */
export class UploadEncodingError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "UploadEncodingError";
  }
}

/**
 * Windows-1252's characters for bytes 0x80 to 0x9F; bytes 0xA0 to 0xFF read as
 * the code points of the same number.
 */
const WINDOWS_1252_HIGH: Record<string, number> = {
  "€": 0x80, "‚": 0x82, "ƒ": 0x83, "„": 0x84, "…": 0x85, "†": 0x86, "‡": 0x87,
  "ˆ": 0x88, "‰": 0x89, "Š": 0x8a, "‹": 0x8b, "Œ": 0x8c, "Ž": 0x8e,
  "‘": 0x91, "’": 0x92, "“": 0x93, "”": 0x94, "•": 0x95, "–": 0x96, "—": 0x97,
  "˜": 0x98, "™": 0x99, "š": 0x9a, "›": 0x9b, "œ": 0x9c, "ž": 0x9e, "Ÿ": 0x9f,
};

/**
 * UTF-8 text read as Windows-1252: a two-byte UTF-8 letter of the Latin-1 range
 * (lead byte C2 or C3: Ø, å, é, °) shows as Â or Ã followed by the character of
 * its second byte (0x80 to 0xBF read as Windows-1252). Ø becomes "Ã˜", å "Ã¥",
 * Æ "Ã†". Real text puts letters after Ã ("SÃO PAULO"), not these characters.
 */
const GARBLED = new RegExp(`[ÂÃ][${Object.keys(WINDOWS_1252_HIGH).join("")}\\u00A0-\\u00BF]`);

/** What a garbled value was before the mix-up, or null when it does not undo. */
export function ungarbled(value: string): string | null {
  const bytes: number[] = [];
  for (const ch of value) {
    const code = ch.codePointAt(0)!;
    if (code < 0x80 || (code >= 0xa0 && code <= 0xff)) bytes.push(code);
    else if (ch in WINDOWS_1252_HIGH) bytes.push(WINDOWS_1252_HIGH[ch]);
    else return null;
  }
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(new Uint8Array(bytes));
  } catch {
    return null;
  }
}

/** The comma-separated value of `line` that holds position `at`, shortened for a message. */
function valueAt(line: string, at: number): string {
  const start = line.lastIndexOf(",", at) + 1;
  const end = line.indexOf(",", at);
  const value = line.slice(start, end === -1 ? undefined : end).replace(/^"|"$/g, "").trim();
  return value.length > 80 ? `${value.slice(0, 77)}...` : value;
}

function countNewlines(text: string, end = text.length): number {
  let n = 0;
  for (let i = text.indexOf("\n"); i !== -1 && i < end; i = text.indexOf("\n", i + 1)) n++;
  return n;
}

/** Length of the valid UTF-8 sequence at `i`: 0 if invalid, -1 if the bytes end inside it. */
function sequenceLength(bytes: Uint8Array, i: number): number {
  const b = bytes[i];
  if (b < 0x80) return 1;
  let n: number;
  let min: number;
  if (b >= 0xc2 && b <= 0xdf) { n = 2; min = 0x80; }
  else if (b >= 0xe0 && b <= 0xef) { n = 3; min = 0x800; }
  else if (b >= 0xf0 && b <= 0xf4) { n = 4; min = 0x10000; }
  else return 0;
  let code = b & (0xff >> (n + 1));
  for (let k = 1; k < n; k++) {
    if (i + k >= bytes.length) return -1;
    const c = bytes[i + k];
    if ((c & 0xc0) !== 0x80) return 0;
    code = (code << 6) | (c & 0x3f);
  }
  if (code < min || (code >= 0xd800 && code <= 0xdfff) || code > 0x10ffff) return 0;
  return n;
}

export class UploadEncodingCheck {
  /** Strict UTF-8 decoding, the fast path; it holds a letter cut between chunks. */
  private readonly decoder = new TextDecoder("utf-8", { fatal: true });
  /** The text after the last newline seen, to show and search a line that spans chunks. */
  private partialLine = "";
  /** The bytes of the line that spans chunks, to locate an invalid byte in it. */
  private partialBytes: Uint8Array = new Uint8Array(0);
  /** Lines completed so far. */
  private lines = 0;

  /** Checks the next bytes of the file; throws UploadEncodingError at the first problem. */
  push(chunk: Uint8Array): void {
    let text: string;
    try {
      text = this.decoder.decode(chunk, { stream: true });
    } catch {
      this.refuseInvalid(chunk);
    }
    this.checkText(text);
    const lastNewline = chunk.lastIndexOf(0x0a);
    this.partialBytes = lastNewline === -1 ? concat(this.partialBytes, chunk) : chunk.slice(lastNewline + 1);
  }

  /** Checks the end of the file: a letter cut off by the end of the file is invalid. */
  end(): void {
    try {
      this.decoder.decode();
    } catch {
      this.refuseInvalid(new Uint8Array(0));
    }
    this.findGarbled(this.partialLine);
  }

  /** Searches whole lines only, so a refusal shows the whole value; the last line waits for end(). */
  private checkText(text: string): void {
    const searched = this.partialLine + text;
    const lastNewline = searched.lastIndexOf("\n");
    if (lastNewline !== -1) this.findGarbled(searched.slice(0, lastNewline));
    this.lines += countNewlines(text);
    this.partialLine = searched.slice(lastNewline + 1);
  }

  /** Refuses the file at the first garbled value in `lines`, which start at line this.lines + 1. */
  private findGarbled(lines: string): void {
    const match = GARBLED.exec(lines);
    if (!match) return;
    const lineStart = lines.lastIndexOf("\n", match.index) + 1;
    const lineEnd = lines.indexOf("\n", match.index);
    const line = lines.slice(lineStart, lineEnd === -1 ? undefined : lineEnd);
    const lineNumber = this.lines + countNewlines(lines, match.index) + 1;
    const value = valueAt(line, match.index - lineStart);
    const was = ungarbled(value);
    throw new UploadEncodingError(
      `The file's text was garbled by an earlier encoding mix-up: line ${lineNumber} has "${value}"` +
        (was && was !== value ? `, which is "${was}" after UTF-8 text was read as Windows-1252` : "") +
        `. Correct the text where the file was made, then save it as UTF-8 and upload it again ` +
        `(in Excel: Save As, "CSV UTF-8 (Comma delimited)"; in LibreOffice: Save As, Character set "Unicode (UTF-8)").`
    );
  }

  /**
   * Finds the first invalid byte in the current line and this chunk, and
   * refuses the file naming its line and value. Only runs once the fast path
   * has found the file invalid.
   */
  private refuseInvalid(chunk: Uint8Array): never {
    const bytes = concat(this.partialBytes, chunk);
    let line = this.lines + 1;
    let lineStart = 0;
    let at = bytes.length;
    let cutOff = false;
    for (let i = 0; i < bytes.length; ) {
      const n = sequenceLength(bytes, i);
      if (n <= 0) { at = i; cutOff = n === -1; break; }
      if (bytes[i] === 0x0a) { line++; lineStart = i + 1; }
      i += n;
    }
    if (cutOff) {
      throw new UploadEncodingError(`The file is not UTF-8: line ${line} has a letter cut off at the end of the file. ${SAVE_AS_UTF8}`);
    }
    const shown = new TextDecoder("windows-1252").decode(bytes.subarray(lineStart, Math.min(at + 1, bytes.length)));
    const hex = Array.from(bytes.subarray(at, at + 3), (b) => b.toString(16).toUpperCase().padStart(2, "0")).join(" ");
    throw new UploadEncodingError(
      `The file is not UTF-8: line ${line} has bytes that are not valid UTF-8 (${hex}) in "${valueAt(shown, shown.length - 1)}". ${SAVE_AS_UTF8}`
    );
  }
}

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  if (a.length === 0) return b;
  const out = new Uint8Array(a.length + b.length);
  out.set(a);
  out.set(b, a.length);
  return out;
}
