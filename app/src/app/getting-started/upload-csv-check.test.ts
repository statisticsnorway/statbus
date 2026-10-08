import {
  explainUploadFailure,
  parseCsvRecords,
  viewColumnsFromOpenApi,
} from "./upload-csv-check";

describe("parseCsvRecords", () => {
  it("reports the line each record starts on, across quoted newlines and CRLF", () => {
    const records = parseCsvRecords(
      'path,name\r\n01,"two\nlines"\r\n02,plain\r\n'
    );
    expect(records).toEqual([
      { fields: ["path", "name"], line: 1 },
      { fields: ["01", "two\nlines"], line: 2 },
      { fields: ["02", "plain"], line: 4 },
    ]);
  });

  it("handles escaped quotes, an unterminated last line and skips blank lines", () => {
    expect(parseCsvRecords('a\n"say ""hi"""\n\nb')).toEqual([
      { fields: ["a"], line: 1 },
      { fields: ['say "hi"'], line: 2 },
      { fields: ["b"], line: 4 },
    ]);
  });
});

describe("explainUploadFailure", () => {
  const failure = (body: unknown) => ({
    status: 400,
    statusText: "Bad Request",
    body: JSON.stringify(body),
  });

  it("names every long cell's first occurrence and counts the rest, by characters not bytes", () => {
    const long = "Æ".repeat(300); // 300 characters, 600 bytes
    const records = parseCsvRecords(
      `path,name\n01,${long}\n02,ok\n03,${"x".repeat(513)}\n`
    );
    expect(
      explainUploadFailure(
        failure({
          code: "22001",
          message: "value too long for type character varying(256)",
        }),
        records,
        [{ name: "path" }, { name: "name", maxLength: 256 }]
      )
    ).toBe(
      "A value is longer than the column allows (256 characters): row 1 (line 2), column name: 300 characters (and 1 more value over the limit)."
    );
  });

  it("only blames columns that carry the reported limit", () => {
    const records = parseCsvRecords(
      `code,name\n${"c".repeat(600)},${"n".repeat(300)}\n`
    );
    expect(
      explainUploadFailure(
        failure({
          code: "22001",
          message: "value too long for type character varying(256)",
        }),
        records,
        [{ name: "code" }, { name: "name", maxLength: 256 }]
      )
    ).toBe(
      "A value is longer than the column allows (256 characters): row 1 (line 2), column name: 300 characters."
    );
  });

  it("recognises a semicolon-separated file instead of listing one giant column", () => {
    const records = parseCsvRecords("path;name\n01;A\n");
    expect(
      explainUploadFailure(
        failure({
          code: "PGRST204",
          message:
            "Could not find the 'path;name' column of 'v' in the schema cache",
        }),
        records,
        [{ name: "path" }, { name: "name" }]
      )
    ).toBe(
      "The file uses semicolons (;) between columns. Save it as a comma-separated CSV and upload it again."
    );
  });

  it("without the view's columns, still names the column instead of 'schema cache'", () => {
    expect(
      explainUploadFailure(
        failure({
          code: "PGRST204",
          message:
            "Could not find the 'Code' column of 'region_upload' in the schema cache",
        }),
        parseCsvRecords("Code\n01\n"),
        null
      )
    ).toBe("The file has a column this step does not accept: Code.");
  });

  it("names the row with an empty required value", () => {
    expect(
      explainUploadFailure(
        failure({
          code: "23502",
          message:
            'null value in column "name" of relation "sector" violates not-null constraint',
        }),
        parseCsvRecords("path,name\n01,A\n02,\n"),
        null
      )
    ).toBe("Row 2 (line 3) has no value in column name, which is required.");
  });

  it("passes any other database message through with its details and hint", () => {
    expect(
      explainUploadFailure(
        failure({
          code: "42601",
          message: "ltree syntax error at character 4",
          details: null,
          hint: null,
        }),
        parseCsvRecords("path,name\nnot a path!,Bad\n"),
        null
      )
    ).toBe("ltree syntax error at character 4");
  });
});

describe("viewColumnsFromOpenApi", () => {
  it("reads the columns and varchar limits PostgREST describes", () => {
    expect(
      viewColumnsFromOpenApi(
        {
          definitions: {
            v: {
              properties: {
                path: { format: "public.ltree" },
                name: { format: "character varying", maxLength: 512 },
              },
            },
          },
        },
        "v"
      )
    ).toEqual([
      { name: "path", maxLength: undefined },
      { name: "name", maxLength: 512 },
    ]);
    expect(viewColumnsFromOpenApi({ definitions: {} }, "v")).toBeNull();
    expect(viewColumnsFromOpenApi(null, "v")).toBeNull();
  });
});
