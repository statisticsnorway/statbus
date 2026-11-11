"use client";

import { useAtomValue } from "jotai";
import { importValidityModeAtom, useImportManager } from "@/atoms/import";

/**
 * The example files for an import page. Which file fits depends on how the
 * rows are dated: a time frame or chosen dates use the plain file; source
 * dates need valid_from and valid_to columns. In Simple mode the page dates
 * by a time frame, so only the plain file is offered, which keeps users from
 * downloading the other one. Advanced offers both, with the one matching the
 * current choice in bold.
 */
export function ImportDemoFiles({
  demoFile,
  sourceDatesDemoFile,
}: {
  /** File name under /demo for rows dated by a frame or chosen dates, e.g. legal_units_demo.csv. */
  readonly demoFile: string;
  /** File name under /demo with valid_from/valid_to columns. */
  readonly sourceDatesDemoFile: string;
}) {
  const mode = useAtomValue(importValidityModeAtom);
  const { importState } = useImportManager();
  const { availableDefinitions, selectedDefinition } = importState;
  const jobProvidedDef = availableDefinitions.find((d) => d.valid_time_from === "job_provided");
  const sourceColumnsDef = availableDefinitions.find((d) => d.valid_time_from === "source_columns");
  const usesSourceDates = selectedDefinition?.valid_time_from === "source_columns";

  const rows = [
    {
      key: "job_provided",
      label: "With a time frame or chosen dates",
      csv: demoFile,
      definition: jobProvidedDef,
      current: !usesSourceDates,
    },
    {
      key: "source_columns",
      label: "With source dates (valid_from, valid_to columns)",
      csv: sourceDatesDemoFile,
      definition: sourceColumnsDef,
      current: usesSourceDates,
    },
  ].filter((row) => mode === "advanced" || row.key === "job_provided");

  return (
    <>
      <table className="text-sm" data-import-demo-files={mode}>
        <thead>
          <tr>
            <th className="pr-4 py-1 text-left"></th>
            <th className="px-2 py-1 text-left">CSV</th>
            <th className="px-2 py-1 text-left">Excel</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.key} className={mode === "advanced" && row.current ? "font-bold" : ""}>
              <td className="pr-4 py-1">{row.label}</td>
              <td className="px-2 py-1">
                <a href={`/demo/${row.csv}`} download={row.csv} className="underline">CSV demo</a>
              </td>
              {row.definition && (
                <td className="px-2 py-1">
                  <a
                    href={`/api/import/template?definitionId=${row.definition.id}&demoFile=${row.csv}`}
                    download
                    className="underline text-blue-600"
                  >
                    Excel demo
                  </a>
                </td>
              )}
            </tr>
          ))}
        </tbody>
      </table>
      <p className="text-sm text-gray-600 mt-3">
        Excel files include code list sheets with dropdown validation. Download an empty Excel template:{" "}
        {rows
          .filter((row) => row.definition)
          .map((row, i) => (
            <span key={row.key}>
              {i > 0 && " / "}
              <a href={`/api/import/template?definitionId=${row.definition!.id}`} download className="underline text-blue-600">
                {row.key === "job_provided" ? "Template" : "Template (with source dates)"}
              </a>
            </span>
          ))}
      </p>
    </>
  );
}
