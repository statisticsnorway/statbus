/**
 * STATBUS-470: the getting-started upload must say plainly what is wrong with
 * a bad file. These drive the real server action (uploadFile) with PostgREST
 * mocked at the fetch boundary, using the responses PostgREST actually gave
 * on the local reproduction (recorded in the ticket).
 */

const fetchWithAuth = jest.fn();
jest.mock("@/context/RestClientStore", () => ({
  fetchWithAuth: (...args: unknown[]) => fetchWithAuth(...args),
  getServerRestClient: async () => ({ url: "http://rest" }),
}));
jest.mock("@/lib/server-logger", () => ({
  createServerLogger: async () => ({ error: () => {}, info: () => {} }),
}));
jest.mock("next/cache", () => ({ revalidatePath: () => {} }));

import { uploadFile } from "./getting-started-server-actions";

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
  return uploadFile("upload-file", VIEW, { error: null }, data);
}

beforeEach(() => fetchWithAuth.mockReset());

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
    const state = await upload(
      form(
        "ActivityCategoryCode,ActivityCategoryLevel,Name\n01,1,Agriculture\n"
      )
    );
    expect(state.error).toBe(
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
    const state = await upload(
      form(
        `path,name,description\n01,Agriculture,ok\n01.1,${"X".repeat(600)},too long name\n`
      )
    );
    expect(state.error).toBe(
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
    const state = await upload(form("path,description\n01.9,no name\n"));
    expect(state.error).toBe("The file has no name column, which is required.");
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
    const state = await upload(form("path,name\n01,A\n"));
    expect(state.error).toBe(
      "The server answered 502 Bad Gateway: <html>502 Bad Gateway</html>"
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
