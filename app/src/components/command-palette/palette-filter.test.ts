import { paletteFilter } from "./palette-filter";

// The command palette lists an item only when every typed word starts a word
// in the item's text, and ranks closer matches first. Owner 2026-11-11: typing
// "api" put "Create import job from definition..." (a, p, i scattered through
// the words) above "Show API key", and he pressed it by mistake.
describe("paletteFilter", () => {
  const createJob = "create job import definition custom advanced";
  const showKey = "show copy api key token";

  it("drops an item whose words only contain the letters scattered", () => {
    expect(paletteFilter(createJob, "api")).toBe(0);
  });

  it("matches a typed word at the start of a word, case-insensitively", () => {
    expect(paletteFilter(showKey, "api")).toBeGreaterThan(0);
    expect(paletteFilter(showKey, "API")).toBeGreaterThan(0);
    expect(paletteFilter("Import Jobs", "imp")).toBeGreaterThan(0);
  });

  it("needs every typed word", () => {
    expect(paletteFilter("Upload Legal Units", "upload legal")).toBeGreaterThan(0);
    expect(paletteFilter("Upload Legal Units", "upload regions")).toBe(0);
  });

  it("ranks a whole-word match above a word-start match, and an earlier word above a later one", () => {
    expect(paletteFilter("Import", "import")).toBeGreaterThan(paletteFilter("Import Jobs", "imp"));
    expect(paletteFilter("Import Jobs", "import")).toBeGreaterThan(paletteFilter(createJob, "import"));
  });

  it("matches a typed word made of the first letters of consecutive words", () => {
    const createJobLabel = "Create import job from definition";
    expect(paletteFilter(createJobLabel, "cij")).toBeGreaterThan(0);
    expect(paletteFilter(createJobLabel, "JFD")).toBeGreaterThan(0);
    expect(paletteFilter(createJobLabel, "cj")).toBe(0);
    expect(paletteFilter(createJobLabel, "api")).toBe(0);
  });

  it("ranks a word start above initials", () => {
    expect(paletteFilter("Import Jobs", "ij")).toBeGreaterThan(0);
    expect(paletteFilter("Import", "imp")).toBeGreaterThan(paletteFilter("Import Jobs", "ij"));
  });

  it("matches the keywords given to an item as well as its text", () => {
    expect(paletteFilter("Reports", "chart", ["statistics", "charts"])).toBeGreaterThan(0);
  });
});
