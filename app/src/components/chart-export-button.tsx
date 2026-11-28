"use client";

import type { Chart } from "highcharts";
import type {} from "highcharts/modules/export-data";
import type {} from "highcharts/modules/exporting";
import { Download } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { downloadChartXlsx } from "@/lib/chart-export";

// Approximate title/subtitle line heights (px) at Highcharts' defaults —
// used to grow exported height so the plot area isn't squeezed to fit them.
const TITLE_LINE_HEIGHT = 24;
const SUBTITLE_LINE_HEIGHT = 16;
const HEADER_BOTTOM_PADDING = 20;

interface ChartExportMenuProps {
  readonly chart: Chart | null;
  readonly title: string;
  readonly subtitle: string;
  readonly hasActiveFilter?: boolean;
  readonly filenameBase: string;
  readonly xlsxDateNumberFormat?: "yyyy" | "yyyy-mm-dd";
  readonly className?: string;
}
function getHeaderHeight(
  title: string,
  subtitle: string,
  hasActiveFilter: boolean
): number {
  const subtitleLineCount = subtitle ? (hasActiveFilter ? 3 : 1) : 0;
  return (
    (title ? TITLE_LINE_HEIGHT : 0) +
    subtitleLineCount * SUBTITLE_LINE_HEIGHT +
    HEADER_BOTTOM_PADDING
  );
}

export const ChartExportButton = ({
  chart,
  title,
  subtitle,
  hasActiveFilter = false,
  filenameBase,
  xlsxDateNumberFormat,
}: ChartExportMenuProps) => {
  const exportPng = () => {
    if (!chart) return;
    void chart.exporting.exportChart(
      { type: "image/png", filename: filenameBase },
      {
        chart: {
          backgroundColor: "#FFFFFF",
          height:
            chart.chartHeight +
            getHeaderHeight(title, subtitle, hasActiveFilter),
        },
        title: { text: title },
        subtitle: {
          text: subtitle,
          align: hasActiveFilter ? "left" : "center",
          x: hasActiveFilter ? 10 : 0,
        },
      }
    );
  };

  const exportCsv = () => {
    if (!chart) return;
    // downloadCSV takes no arguments — it reads the filename off the
    // chart's own options, so set it there first.
    chart.update({ exporting: { filename: filenameBase } }, false);
    chart.exporting.downloadCSV();
  };

  const exportXlsx = () => {
    if (!chart) return;
    void downloadChartXlsx(
      chart.exporting.getDataRows(false),
      filenameBase,
      xlsxDateNumberFormat
    );
  };

  // The app's download button, as on Regions and Search: the down-arrow and the word, outlined
  // (owner 2026-11-28 14:41: a hamburger did not say download).
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm" className="flex items-center gap-1.5" data-chart-download="">
          <Download className="h-4 w-4" />
          Download
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start">
        <DropdownMenuItem onClick={exportPng}>Download PNG</DropdownMenuItem>
        <DropdownMenuItem onClick={exportCsv}>Download CSV</DropdownMenuItem>
        <DropdownMenuItem onClick={exportXlsx}>Download XLSX</DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
};
