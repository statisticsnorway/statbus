/**
 * e1z8va: an import upload refuses a file that is not UTF-8, or that holds text
 * once read as Windows-1252 (Ø stored as "Ã˜"), naming the line and the value,
 * and lets a correct UTF-8 file with Ø, Å and Æ through unchanged.
 */
import { UploadEncodingCheck, UploadEncodingError, ungarbled } from "./upload-encoding";

const utf8 = (s: string) => new TextEncoder().encode(s);
const windows1252 = (s: string) => Uint8Array.from(Array.from(s, (c) => c.charCodeAt(0)));

/** Runs the check over `bytes` cut into chunks of `size` bytes; returns the refusal or null. */
function check(bytes: Uint8Array, size = bytes.length): UploadEncodingError | null {
  const c = new UploadEncodingCheck();
  try {
    for (let i = 0; i < bytes.length; i += size) c.push(bytes.subarray(i, i + size));
    c.end();
    return null;
  } catch (e) {
    if (e instanceof UploadEncodingError) return e;
    throw e;
  }
}

const header = "tax_ident,name,birth_date\n";
const goodRows = "923609016,RØRSERVICE AS,2019-01-01\n912345678,BLÅBÆR ÆRØ AS,2020-05-05\n987654321,SÃO PAULO COMÉRCIO LTDA,2021-02-02\n";

describe("a correct UTF-8 file", () => {
  it.each([1, 2, 3, 7, 64, 100000])("passes whole, with Ø, Å, Æ and SÃO PAULO, in chunks of %i bytes", (size) => {
    expect(check(utf8(header + goodRows), size)).toBeNull();
  });

  it("passes with a byte order mark and Windows line ends", () => {
    expect(check(utf8("\uFEFF" + (header + goodRows).replace(/\n/g, "\r\n")))).toBeNull();
  });
});

describe("a file that is not UTF-8 (saved as Windows-1252 or Latin-1)", () => {
  const file = windows1252(header + "923609016,OK AS,2019-01-01\n912345678,RØRSERVICE AS,2020-05-05\n");

  it.each([1, 5, 1000])("is refused at the line and value of the first invalid byte, in chunks of %i bytes", (size) => {
    const refusal = check(file, size);
    expect(refusal?.message).toMatch(/^The file is not UTF-8: line 3 has bytes that are not valid UTF-8 \(D8 /);
    expect(refusal?.message).toContain('"RØ"');
    expect(refusal?.message).toContain("Save the file as UTF-8");
  });

  it("is refused when the file ends inside a letter", () => {
    const cut = utf8(header + "1,RØ").subarray(0, utf8(header + "1,RØ").length - 1);
    expect(check(cut)?.message).toMatch(/^The file is not UTF-8: line 2 has a letter cut off at the end of the file/);
  });
});

describe("a UTF-8 file whose text was once read as Windows-1252", () => {
  const garbled = header + "923609016,OK AS,2019-01-01\n913000001,24T RÃ˜RSERVICE AS KONKURSBO,2020-05-05\n";

  it.each([1, 3, 1000])("is refused at the first garbled line, naming the value and what it was, in chunks of %i bytes", (size) => {
    const refusal = check(utf8(garbled), size);
    expect(refusal?.message).toBe(
      'The file\'s text was garbled by an earlier encoding mix-up: line 3 has "24T RÃ˜RSERVICE AS KONKURSBO", ' +
        'which is "24T RØRSERVICE AS KONKURSBO" after UTF-8 text was read as Windows-1252. ' +
        "Correct the text where the file was made, then save it as UTF-8 and upload it again " +
        '(in Excel: Save As, "CSV UTF-8 (Comma delimited)"; in LibreOffice: Save As, Character set "Unicode (UTF-8)").'
    );
  });

  it.each([
    ["Ø", "Ã˜"],
    ["Å", "Ã…"],
    ["Æ", "Ã†"],
    ["ø", "Ã¸"],
    ["å", "Ã¥"],
    ["æ", "Ã¦"],
    ["é", "Ã©"],
  ])("finds %s garbled as %s", (letter, garbledForm) => {
    expect(check(utf8(`${header}1,B${garbledForm}R AS,2020-01-01\n`))?.message).toContain(`"B${letter}R AS"`);
  });
});

describe("ungarbled", () => {
  it("undoes the mix-up of a garbled value", () => {
    expect(ungarbled("BLÃ…BÃ†R")).toBe("BLÅBÆR");
  });
  it("leaves no answer for text that was not garbled", () => {
    expect(ungarbled("SÃO PAULO")).toBeNull();
  });
});
