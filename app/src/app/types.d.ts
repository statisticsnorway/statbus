import { Tables } from "@/lib/database.types";

type Period = Tables<"period_active">;

interface ExternalIdents {
  [key: string]: number | string;
}

interface StatsSummary {
  [key: string]: {
    [key: string]: number | string;
  };
}

interface StatisticalUnit extends Tables<"statistical_unit"> {
  external_idents: ExternalIdents;
  stats_summary: StatsSummary;
}