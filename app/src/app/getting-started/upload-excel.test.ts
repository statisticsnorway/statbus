import { csvTextToExcelBlob } from "./upload-excel";
import { convertExcelToCsvBlob } from "@/lib/excel-to-csv";

// The getting-started uploads take Excel (owner 2026-11-26): an example made as Excel from its CSV,
// read back the way an uploaded workbook is read, gives the same rows. Codes keep their leading
// zero (a region's path 03), as every cell is text.
describe("csvTextToExcelBlob", () => {
  it("round-trips a regions file through Excel with its codes and decimals as written", async () => {
    const csv = "path,name,center_latitude,center_longitude,center_altitude\n03,Oslo,59.913868,10.752245,23\n46.4601,Bergen,60.391263,5.322054,\n";
    const excel = await csvTextToExcelBlob(csv, "Regions");
    const back = await (await convertExcelToCsvBlob(await excel.arrayBuffer())).text();
    expect(back.trim().split("\n")).toEqual([
      "path,name,center_latitude,center_longitude,center_altitude",
      "03,Oslo,59.913868,10.752245,23",
      "46.4601,Bergen,60.391263,5.322054,",
    ]);
  });
});
