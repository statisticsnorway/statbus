import type { TimeFrame } from "@/lib/time-frame";

/** The job fields that say where its rows apply and where they come from (public.import_job). */
export interface JobValiditySource {
  time_frame_ident: string | null;
  default_valid_from: string | null;
  default_valid_to: string | null;
  default_data_source_code: string | null;
  edit_comment: string | null;
}

export interface JobSummary {
  /** "Previous frame (2025)", "Chosen dates" or "Source dates". */
  timeFrame: string;
  /** "2025-01-01 – 2025-12-31", or the file's columns for source dates. */
  period: string;
  /** "survey – Survey Data", or null when the job names none (rows bring their own). */
  dataSource: string | null;
  comment: string | null;
}

const fmtTo = (to: string | null) => (!to || to === "infinity" ? "Present" : to);

/**
 * What a job was set to on the import page, in the words of the Time frame
 * panel (components/time-frame-panel.tsx). One summary for every screen that
 * shows a job: the upload page, the job list, the job's data page.
 *
 * A job names a time frame (time_frame_ident, its dates derived from the
 * frame), or carries chosen dates (default_valid_from/to, no frame), or
 * neither: its definition reads valid_from and valid_to from the file.
 */
export function summarizeJob(
  job: JobValiditySource,
  timeFrames: readonly Pick<TimeFrame, "ident" | "name">[],
  dataSources: readonly { code: string | null; name: string | null }[]
): JobSummary {
  const frame = job.time_frame_ident ? timeFrames.find((f) => f.ident === job.time_frame_ident) : undefined;
  const source = job.default_data_source_code
    ? dataSources.find((d) => d.code === job.default_data_source_code)
    : undefined;
  const dataSource = job.default_data_source_code
    ? `${job.default_data_source_code} – ${source?.name ?? "unknown source"}`
    : null;
  const comment = job.edit_comment?.trim() ? job.edit_comment.trim() : null;

  if (job.time_frame_ident) {
    return {
      // A frame retired since the job was made still shows by its ident.
      timeFrame: frame?.name ?? job.time_frame_ident,
      period: `${job.default_valid_from ?? "?"} – ${fmtTo(job.default_valid_to)}`,
      dataSource,
      comment,
    };
  }
  if (job.default_valid_from || job.default_valid_to) {
    return {
      timeFrame: "Chosen dates",
      period: `${job.default_valid_from ?? "?"} – ${fmtTo(job.default_valid_to)}`,
      dataSource,
      comment,
    };
  }
  return {
    timeFrame: "Source dates",
    period: "From the file (valid_from, valid_to)",
    dataSource,
    comment,
  };
}
