"use client";

import React from "react";
import { useTimeFrame } from "@/atoms/app-derived";
import { useDetailsPageData } from "@/atoms/edits";
import { summarizeJob, type JobValiditySource } from "@/lib/import-job-summary";

interface ImportJobDetailsProps {
  /** The job's dating, source and comment fields, and its description. */
  job: JobValiditySource & { description: string | null };
  /** The definition the job was made from; only its name is shown. */
  definition: { name: string | null } | null;
}

/**
 * The job as it was set on the import page: its Time frame and period, Data
 * source and Comment (lib/import-job-summary.ts), and its definition. Shown
 * on the upload page and the job's data page, so the job reads the same
 * everywhere it appears.
 */
export function ImportJobDetails({ job, definition }: ImportJobDetailsProps) {
  const { timeFrames } = useTimeFrame();
  const { dataSources } = useDetailsPageData();
  const summary = summarizeJob(job, timeFrames, dataSources);
  const rows: [string, React.ReactNode][] = [
    ["Time frame", <>{summary.timeFrame} <span className="text-zinc-500">· {summary.period}</span></>],
    ["Data source", summary.dataSource ?? <span className="text-zinc-500">From the file or the definition</span>],
    ...(summary.comment ? ([["Comment", <span key="c" className="whitespace-pre-wrap">{summary.comment}</span>]] as [string, React.ReactNode][]) : []),
    ["Definition", definition?.name ?? job.description],
  ];

  return (
    <div className="rounded-md border border-zinc-200 bg-white p-4" data-import-job-summary>
      <h3 className="mb-3 font-medium">Import Configuration</h3>
      <dl className="grid grid-cols-[8rem_1fr] gap-x-4 gap-y-1.5 text-sm">
        {rows.map(([label, value]) => (
          <React.Fragment key={label}>
            <dt className="text-zinc-500">{label}</dt>
            <dd className="text-right font-medium" data-summary-field={label}>{value}</dd>
          </React.Fragment>
        ))}
      </dl>
    </div>
  );
}
