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

// jsonb_stats aggregate types — see jsonb_stats README.md "Structures in Detail"

/** Numeric aggregate (int_agg, float_agg, dec2_agg, nat_agg) */
interface NumericStatAgg {
  type: "int_agg" | "float_agg" | "dec2_agg" | "nat_agg";
  count: number;
  sum: number;
  min: number;
  max: number;
  mean: number;
  sum_sq_diff: number;
  variance: number | null;
  stddev: number | null;
  coefficient_of_variation_pct: number | null;
}

/** Categorical aggregate (str_agg, bool_agg) */
interface CategoricalStatAgg {
  type: "str_agg" | "bool_agg";
  counts: { [value: string]: number };
}

/** Array aggregate */
interface ArrayStatAgg {
  type: "arr_agg";
  count: number;
  counts: { [element: string]: number };
}

/** Date aggregate */
interface DateStatAgg {
  type: "date_agg";
  counts: { [isoDate: string]: number };
  min: string;
  max: string;
}

type StatAgg = NumericStatAgg | CategoricalStatAgg | ArrayStatAgg | DateStatAgg;

/** stats_agg object: { type: "stats_agg", [statCode]: StatAgg } */
interface StatsSummary {
  [statCode: string]: StatAgg;
}

interface StatisticalUnit extends Tables<"statistical_unit"> {
  external_idents: ExternalIdents;
  stats_summary: StatsSummary;
}
