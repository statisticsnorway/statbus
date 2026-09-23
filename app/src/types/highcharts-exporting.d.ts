import type { ExportingOptions, Options } from "highcharts";

declare module "highcharts" {
  interface Exporting {
    exportChart(
      exportingOptions?: ExportingOptions,
      chartOptions?: Options
    ): Promise<void>;
  }
}
