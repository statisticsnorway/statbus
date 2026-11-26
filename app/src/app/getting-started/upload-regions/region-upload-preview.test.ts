import { previewRegionUpload, type StoredRegion } from "./region-upload-preview";

// 5yxn4w: the check step before a region file is stored. It follows admin.region_upload_upsert
// (test/sql/414): a row changes only what it gives.
const stored: StoredRegion[] = [
  { path: "03", name: "Oslo", center_latitude: "59.913868", center_longitude: "10.752245", center_altitude: "23.0" },
  { path: "11", name: "Rogaland", center_latitude: null, center_longitude: null, center_altitude: null },
  { path: "11.01", name: "Eigersund", center_latitude: null, center_longitude: null, center_altitude: null },
];
const rows = (...lines: string[][]) => lines.map((fields, i) => ({ fields, line: i + 2 }));

describe("previewRegionUpload", () => {
  it("sorts a file's rows into new, renamed, coordinates set, moved and unchanged, and counts the regions it leaves alone", () => {
    const p = previewRegionUpload(
      ["path", "name", "center_latitude", "center_longitude", "center_altitude"],
      rows(
        ["03", "Oslo", "59.913868", "10.752245", "23"],
        ["11", "Rogaland fylke", "", "", ""],
        ["11.01", "", "58.463409", "5.975909", ""],
        ["11.03", "Stavanger", "58.97929", "5.707019", ""]
      ),
      stored
    );
    expect({
      added: p.added.map((r) => r.path),
      renamed: p.renamed.map((r) => [r.path, r.oldName, r.name]),
      set: p.coordinatesSet.map((r) => r.path),
      moved: p.coordinatesMoved.map((r) => r.path),
      unchanged: p.unchanged,
      notInFile: p.notInFile,
      errors: p.errors,
    }).toEqual({
      added: ["11.03"],
      renamed: [["11", "Rogaland", "Rogaland fylke"]],
      set: ["11.01", "11.03"],
      moved: [],
      unchanged: 1,
      notInFile: 0,
      errors: [],
    });
  });

  it("sees a moved centre and leaves out the regions a coordinates file does not name", () => {
    const p = previewRegionUpload(["path", "center_latitude", "center_longitude"], rows(["03", "59.9", "10.75"]), stored);
    expect([p.coordinatesMoved.map((r) => r.name), p.notInFile]).toEqual([["Oslo"], 2]);
  });

  it("names each wrong row with its file line, as the upload would refuse it", () => {
    const p = previewRegionUpload(
      ["path", "name", "center_latitude", "center_longitude"],
      rows(
        ["11.98", "", "58", "6"],
        ["12.01", "Nowhere", "", ""],
        ["11.01", "", "91", "6"],
        ["11.01", "", "58", ""],
        ["03", "", "59,9", "10,7"]
      ),
      stored
    );
    expect(p.errors).toEqual([
      { line: 2, message: "11.98: a new region needs a name" },
      { line: 3, message: "12.01: its parent 12 is not in the region list, nor above it in the file" },
      { line: 4, message: "11.01: latitude 91 is outside -90 to 90" },
      { line: 5, message: "11.01: the path is in the file twice" },
      { line: 6, message: "03: a coordinate is not a number (use a dot for decimals)" },
    ]);
  });

  it("accepts a new region whose parent comes earlier in the same file", () => {
    const p = previewRegionUpload(["path", "name"], rows(["12", "Hordaland"], ["12.01", "Bergen"]), stored);
    expect([p.added.map((r) => r.path), p.errors]).toEqual([["12", "12.01"], []]);
  });

  it("names unknown columns, such as a misspelt header", () => {
    const p = previewRegionUpload(["path", "name", "latitude"], rows(["03", "Oslo", "59"]), stored);
    expect(p.errors[0]).toEqual({
      line: 1,
      message: "Unknown column latitude. The columns are path, name, center_latitude, center_longitude, center_altitude.",
    });
  });
});
