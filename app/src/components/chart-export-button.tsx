"use client";

import type { Chart } from "highcharts";
import type {} from "highcharts/modules/exporting";
import { Menu } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

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
  readonly className?: string;
}
type ExportingWithData = NonNullable<Chart["exporting"]> & {
    downloadCSV?: () => void;
  };

function getHeaderHeight(title: string, subtitle: string, hasActiveFilter: boolean): number {
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
}: ChartExportMenuProps) => {
  const exportPng = () => {
    if (!chart) return;
    (chart.exporting as ExportingWithData | undefined)?.exportChart(
      { type: "image/png", filename: filenameBase },
      {
        chart: {
          backgroundColor: "#FFFFFF",
          height: chart.chartHeight + getHeaderHeight(title, subtitle, hasActiveFilter),
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
    (chart.exporting as ExportingWithData | undefined)?.downloadCSV?.();
  };
  
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" title="Export chart">
          <Menu className="h-4 w-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onClick={exportPng}>
          Download PNG
        </DropdownMenuItem>
        <DropdownMenuItem onClick={exportCsv}>Download CSV</DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
};