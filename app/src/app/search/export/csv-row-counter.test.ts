import { createCsvRowCounter } from "./csv-row-counter";

const encoder = new TextEncoder();

function feed(counter: ReturnType<typeof createCsvRowCounter>, text: string) {
  counter.push(encoder.encode(text));
}

describe("createCsvRowCounter", () => {
  it("counts header and simple records", () => {
    const counter = createCsvRowCounter();
    feed(counter, "name,id\nalpha,1\nbeta,2\n");
    expect(counter.lines).toBe(3);
    expect(counter.records).toBe(2);
  });

  it("ignores newlines inside quoted fields (embedded newlines)", () => {
    const counter = createCsvRowCounter();
    feed(counter, 'name,note\nalpha,"line one\nline two"\nbeta,x\n');
    expect(counter.records).toBe(2);
  });

  it("handles escaped quotes without losing quote state", () => {
    const counter = createCsvRowCounter();
    feed(counter, 'name\n"say ""hi""\ninside",\nnext\n');
    expect(counter.records).toBe(2);
  });

  it("carries quote state across chunk boundaries", () => {
    const counter = createCsvRowCounter();
    // Split inside a quoted field, inside an escape, and mid-newline run.
    // A partial (still streaming) line counts as one record in progress.
    feed(counter, 'name\n"unterminated');
    expect(counter.records).toBe(1);
    feed(counter, ' field\nwith newline",x\nla');
    expect(counter.records).toBe(2);
    feed(counter, "st,2\n");
    expect(counter.records).toBe(2);
  });

  it("splits a quoted field byte-by-byte and still counts correctly", () => {
    const csv = 'a,b\n"x\ny""z",2\nq,3\n';
    const counter = createCsvRowCounter();
    for (const ch of csv) {
      feed(counter, ch);
    }
    expect(counter.records).toBe(2);
  });

  it("never reports a negative record count", () => {
    const counter = createCsvRowCounter();
    expect(counter.records).toBe(0);
  });

  it("counts the last record even without a trailing newline (PostgREST style)", () => {
    const counter = createCsvRowCounter();
    feed(counter, "name,id\nalpha,1\nbeta,2");
    expect(counter.records).toBe(2);
  });

  it("counts a header-only response as zero records", () => {
    const counter = createCsvRowCounter();
    feed(counter, "name,id");
    expect(counter.records).toBe(0);
  });
});
