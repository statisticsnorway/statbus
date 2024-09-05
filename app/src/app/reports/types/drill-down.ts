import { StatsSummary } from "@/app/types";

export type DrillDown = {
  available: {
    region: DrillDownPoint[];
    activity_category: DrillDownPoint[];
  };
  unit_type: "enterprise" | "legal_unit" | "establishment";
  breadcrumb: {
    region: DrillDownPoint[] | null;
    activity_category: DrillDownPoint[] | null;
  };
};

export type DrillDownPoint = {
  code: string;
  name: string;
  path: string;
  count: number;
  stats_summary: StatsSummary;
  label: string;
  has_children: boolean;
};
