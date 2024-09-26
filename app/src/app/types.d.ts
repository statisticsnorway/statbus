import { Tables } from "@/lib/database.types";

type TimeContext = Tables<"time_context">;

type StatDefinition = Tables<"stat_definition">;
type ExternalIdentType = Tables<"external_ident_type">;

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
