"use client";

import React from "react";
import { useTimeFrame } from "@/atoms/app-derived";
import { useDetailsPageData } from "@/atoms/edits";
import { InfoPopover } from "@/components/info-popover";
import { summarizeJob, type JobValiditySource } from "@/lib/import-job-summary";
import { cn } from "@/lib/utils";

interface ImportJobDetailsProps {
  /** The job's dating, source and comment fields, its description and data table. */
  job: JobValiditySource & { description: string | null; data_table_name?: string | null };
  /** The definition the job was made from; only its name is shown. */
  definition: { name: string | null } | null;
  className?: string;
}

/**
 * One line under a job page's heading: Definition · Description · Time frame
 * · Data source · Table · Comment, each a muted label and its value
 * (lib/import-job-summary.ts). The data source shows its code with an (i)
 * for the name, as in the job list; a comment is cut short with an (i) to
 * read it all. On a narrow screen the line wraps between items, never inside
 * one. Used by the upload pages and the job's data page.
 */
export function ImportJobDetails({ job, definition, className }: ImportJobDetailsProps) {
  const { timeFrames } = useTimeFrame();
  const { dataSources } = useDetailsPageData();
  const summary = summarizeJob(job, timeFrames, dataSources);

  const items: { label: string; value: React.ReactNode }[] = [
    { label: "Definition", value: definition?.name ?? "—" },
    { label: "Description", value: job.description ?? "—" },
    { label: "Time frame", value: <>{summary.timeFrame}{summary.period && <span className="text-zinc-500"> ({summary.period})</span>}</> },
    {
      label: "Data source",
      value: (
        <span className="inline-flex items-center gap-1">
          {job.default_data_source_code ? (
            <span className="font-mono">{job.default_data_source_code}</span>
          ) : (
            <span>From file</span>
          )}
          <InfoPopover label="About the data source" title="Data source" side="bottom">
            {summary.dataSource ?? "The job names no source: each row's own source is used, or the import definition's."}
          </InfoPopover>
        </span>
      ),
    },
    ...(job.data_table_name ? [{ label: "Table", value: <span className="font-mono">{job.data_table_name}</span> }] : []),
    ...(summary.comment
      ? [{
          label: "Comment",
          value: (
            <span className="inline-flex max-w-[20rem] items-center gap-1">
              <span className="truncate">{summary.comment}</span>
              <InfoPopover label="Read the whole comment" title="Comment" side="bottom">
                <span className="whitespace-pre-wrap">{summary.comment}</span>
              </InfoPopover>
            </span>
          ),
        }]
      : []),
  ];

  return (
    <p className={cn("flex flex-wrap items-center gap-x-1.5 gap-y-0.5 text-sm", className)} data-import-job-summary>
      {items.map((item, i) => (
        <span key={item.label} className="inline-flex items-center gap-1 whitespace-nowrap" data-summary-field={item.label}>
          {i > 0 && <span className="text-zinc-300" aria-hidden>·</span>}
          <span className="text-zinc-500">{item.label}</span>
          <span className="text-zinc-900">{item.value}</span>
        </span>
      ))}
    </p>
  );
}
