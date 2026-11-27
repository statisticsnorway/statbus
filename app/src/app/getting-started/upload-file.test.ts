/**
 * STATBUS-470, 7dw69p: a getting-started upload goes from the browser straight to PostgREST and says
 * plainly what came of it. These drive the real uploadFile with PostgREST mocked at the fetch
 * boundary, using the responses PostgREST actually gave on the local reproductions (recorded in the
 * tickets).
 */
import { readableSize, uploadFile } from "./upload-file";

const fetchWithAuth = jest.fn();
const report = jest.fn();

const VIEW = "activity_category_enabled_custom" as const;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** PostgREST's OpenAPI document, reduced to the view under test. */
const OPENAPI = json(200, {
  definitions: {
    activity_category_enabled_custom: {
      properties: {
        path: { format: "public.ltree" },
        name: { format: "character varying", maxLength: 512 },
        description: { format: "text" },
      },
    },
  },
});

function form(content: string | null, name = "codes.csv"): FormData {
  const data = new FormData();
  if (content !== null) {
    data.set("upload-file", new File([content], name, { type: "text/csv" }));
  }
  return data;
}

async function upload(data: FormData) {
  return uploadFile(data.get("upload-file"), VIEW, {
    restUrl: "http://rest",
    fetch: fetchWithAuth,
    report,
  });
}

/** The file named in every failure: codes.csv and its size. */
const stored = (content: string, name = "codes.csv") =>
  `${name} (${readableSize(new Blob([content]).size)}) was not stored. `;

beforeEach(() => {
  fetchWithAuth.mockReset();
  report.mockReset();
});

describe("uploadFile: a bad file says plainly what is wrong", () => {
  it("no file selected: says so and sends nothing", async () => {
    const state = await upload(form(null));
    expect(state.error).toBe(
      "No file selected. Choose a CSV file, then press Upload."
    );
    expect(fetchWithAuth).not.toHaveBeenCalled();
  });

  it("an empty file: says it is empty, never a parse error", async () => {
    const state = await upload(form(""));
    expect(state.error).toBe("The file codes.csv is empty.");
    expect(fetchWithAuth).not.toHaveBeenCalled();
  });

  it("a header with no data rows: says so instead of 'succeeding' with nothing imported", async () => {
    const state = await upload(form("path,name,description\n"));
    expect(state.error).toBe(
      "The file codes.csv has a header row but no data rows."
    );
    expect(state.success).toBeUndefined();
    expect(fetchWithAuth).not.toHaveBeenCalled();
  });

  it("columns the view does not accept: names every one, and what it expects", async () => {
    fetchWithAuth
      .mockResolvedValueOnce(
        json(400, {
          code: "PGRST204",
          details: null,
          hint: null,
          message:
            "Could not find the 'ActivityCategoryCode' column of 'activity_category_enabled_custom' in the schema cache",
        })
      )
      .mockResolvedValueOnce(OPENAPI);
    const file =
      "ActivityCategoryCode,ActivityCategoryLevel,Name\n01,1,Agriculture\n";
    const state = await upload(form(file));
    expect(state.error).toBe(
      stored(file) +
        "The file has columns this step does not accept: ActivityCategoryCode, ActivityCategoryLevel, Name. " +
        "The accepted columns are: path, name, description. Column names are case-sensitive " +
        "(Name could be name)."
    );
    expect(state.error).not.toMatch(/schema cache/);
  });

  it("a value too long: names the row, the column, its length and the limit", async () => {
    fetchWithAuth.mockResolvedValueOnce(
      json(400, {
        code: "22001",
        details: null,
        hint: null,
        message: "value too long for type character varying(512)",
      })
    );
    const file = `path,name,description\n01,Agriculture,ok\n01.1,${"X".repeat(600)},too long name\n`;
    const state = await upload(form(file));
    expect(state.error).toBe(
      stored(file) +
        "A value is longer than the column allows (512 characters): " +
        "row 2 (line 3), column name: 600 characters."
    );
  });

  it("a missing required column: names it", async () => {
    fetchWithAuth.mockResolvedValueOnce(
      json(400, {
        code: "23502",
        details: null,
        hint: null,
        message:
          'null value in column "name" of relation "activity_category" violates not-null constraint',
      })
    );
    const file = "path,description\n01.9,no name\n";
    const state = await upload(form(file));
    expect(state.error).toBe(
      stored(file) + "The file has no name column, which is required."
    );
  });

  it("a byte-order mark (as Excel writes it) is not part of the first column name", async () => {
    fetchWithAuth.mockResolvedValueOnce(new Response(null, { status: 201 }));
    const state = await upload(
      form("\uFEFFpath,name,description\n01,Agriculture,ok\n")
    );
    expect(state).toEqual({ error: null, success: true });
    const body = fetchWithAuth.mock.calls[0][1].body as string;
    expect(body.startsWith("path,name,description")).toBe(true);
  });

  it("an error body that is not JSON still names the status, instead of a generic failure", async () => {
    fetchWithAuth.mockResolvedValueOnce(
      new Response("<html>502 Bad Gateway</html>", {
        status: 502,
        statusText: "Bad Gateway",
      })
    );
    const file = "path,name\n01,A\n";
    const state = await upload(form(file));
    expect(state.error).toBe(
      stored(file) +
        "The server answered 502 Bad Gateway: <html>502 Bad Gateway</html>"
    );
    expect(report).toHaveBeenCalledWith(
      `upload to ${VIEW} failed`,
      expect.objectContaining({ file: "codes.csv", status: 502, rows: 1 })
    );
  });

  it("a file over 1 MB goes to PostgREST whole, in one request (Uganda's region file, 7dw69p)", async () => {
    fetchWithAuth.mockResolvedValueOnce(new Response(null, { status: 201 }));
    const rows = Array.from(
      { length: 60000 },
      (_, i) => `01.${i},Parish ${i} of a district`
    );
    const file = `path,name\n${rows.join("\n")}\n`;
    expect(file.length).toBeGreaterThan(1024 * 1024);
    const state = await upload(form(file, "regions.csv"));
    expect(state).toEqual({ error: null, success: true });
    expect(fetchWithAuth).toHaveBeenCalledTimes(1);
    expect(fetchWithAuth.mock.calls[0][1].body).toBe(file);
  });

  it("a statement timeout: says the file took too long and how to store it in parts", async () => {
    fetchWithAuth.mockResolvedValueOnce(
      json(500, {
        code: "57014",
        details: null,
        hint: null,
        message: "canceling statement due to statement timeout",
      })
    );
    const file = "path,name\n01,A\n02,B\n";
    const state = await upload(form(file, "regions.xlsx"));
    expect(state.error).toBe(
      stored(file, "regions.xlsx") +
        "Storing 2 rows took longer than the server allows, so nothing was stored. " +
        "Split the file into smaller files and upload them one after another: each file adds to what is stored."
    );
  });

  it("too large for the server (413): says so and how to store it in parts", async () => {
    fetchWithAuth.mockResolvedValueOnce(
      new Response("Request Entity Too Large", { status: 413 })
    );
    const file = "path,name\n01,A\n";
    const state = await upload(form(file));
    expect(state.error).toBe(
      stored(file) +
        "The server refused the file as too large (413). Split it into smaller files and upload them one after another: each file adds to what is stored."
    );
  });

  it("the connection lost: says nothing was stored and to try again", async () => {
    fetchWithAuth.mockRejectedValueOnce(
      new TypeError("NetworkError when attempting to fetch resource.")
    );
    const file = "path,name\n01,A\n";
    const state = await upload(form(file));
    expect(state.error).toBe(
      stored(file) +
        "The connection to the server was lost before it answered (NetworkError when attempting to fetch resource.). " +
        "Nothing was stored; check the network and try again."
    );
  });

  it("a good file uploads with one request", async () => {
    fetchWithAuth.mockResolvedValueOnce(new Response(null, { status: 201 }));
    const state = await upload(form("path,name\n01,Agriculture\n"));
    expect(state).toEqual({ error: null, success: true });
    expect(fetchWithAuth).toHaveBeenCalledTimes(1);
    expect(fetchWithAuth.mock.calls[0][0]).toBe(`http://rest/${VIEW}`);
  });
});
