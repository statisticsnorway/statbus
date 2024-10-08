import { Tables } from "@/lib/database.types";

type TimeContextRow = Tables<"time_context">;
type StatDefinitionRow = Tables<"stat_definition">;
type ExternalIdentRow = Tables<"external_ident_type">;

type TimeContextRows = TimeContextRow[];
type StatDefinitionRows = StatDefinitionRow[];
type ExternalIdentRows = ExternalIdentRow[];

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
