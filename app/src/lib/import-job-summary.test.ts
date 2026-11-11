import { summarizeJob, type JobValiditySource } from "./import-job-summary";

const frames = [
  { ident: "live", name: "Live frame (2026)" },
  { ident: "prev", name: "Previous frame (2025)" },
];
const sources = [{ code: "survey", name: "Survey Data" }];
const job = (o: Partial<JobValiditySource>): JobValiditySource => ({
  time_frame_ident: null,
  default_valid_from: null,
  default_valid_to: null,
  default_data_source_code: null,
  edit_comment: null,
  ...o,
});

describe("summarizeJob", () => {
  it("names the frame and its period, the source by code and name, and the comment", () => {
    expect(
      summarizeJob(
        job({ time_frame_ident: "prev", default_valid_from: "2025-01-01", default_valid_to: "2025-12-31", default_data_source_code: "survey", edit_comment: " survey corrections " }),
        frames,
        sources
      )
    ).toEqual({
      timeFrame: "Previous frame (2025)",
      period: "2025-01-01 – 2025-12-31",
      dataSource: "survey – Survey Data",
      comment: "survey corrections",
    });
  });

  it("shows an open end as Present", () => {
    expect(summarizeJob(job({ time_frame_ident: "live", default_valid_from: "2026-01-01", default_valid_to: "infinity" }), frames, sources))
      .toMatchObject({ timeFrame: "Live frame (2026)", period: "2026-01-01 – Present", dataSource: null, comment: null });
  });

  it("calls dates without a frame Chosen dates", () => {
    expect(summarizeJob(job({ default_valid_from: "2024-03-01", default_valid_to: "2024-06-30" }), frames, sources))
      .toMatchObject({ timeFrame: "Chosen dates", period: "2024-03-01 – 2024-06-30" });
  });

  it("calls a job with neither Source dates", () => {
    expect(summarizeJob(job({}), frames, sources))
      .toMatchObject({ timeFrame: "Source dates", period: "From the file (valid_from, valid_to)" });
  });

  it("shows a frame that no longer exists by its ident", () => {
    expect(summarizeJob(job({ time_frame_ident: "y_2019", default_valid_from: "2019-01-01", default_valid_to: "2019-12-31" }), frames, sources))
      .toMatchObject({ timeFrame: "y_2019" });
  });
});
