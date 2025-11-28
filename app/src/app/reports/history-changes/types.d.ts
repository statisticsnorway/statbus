declare interface StatisticalHistoryHighcharts {
  series: Array<{
    code: string;
    name: string;
    data: [number, number][];
    priority: number;
  }>;
  unit_type: UnitType;
  resolution: Enums<"history_resolution">;
  filtered_series: string[];
  available_series: Array<{
    code: string;
    name: string;
    priority: number;
  }>;
}