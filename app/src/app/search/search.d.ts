import { TimeContext } from "../types";
import { Tables } from "@/lib/database.types";
import { StatisticalUnit } from "@/app/types";

export type SearchFilterOption = {
  readonly label: string;
  readonly value: string | null;
  readonly humanReadableValue?: string;
  readonly className?: string;
  readonly icon?: React.ReactNode;
};

export type SearchOrder = {
  readonly name: string;
  readonly direction: "asc" | "desc.nullslast";
};

export type SearchPagination = {
  readonly pageSize: number;
  readonly pageNumber: number;
};

export interface SearchState {
  readonly apiSearchParams: Record<string, string | null>;
  readonly appSearchParams: Record<string, (string | null)[] | undefined>;
  readonly order: SearchOrder;
  readonly pagination: SearchPagination;
  readonly valid_on: string; // Should be date, but is string from database, so we do the same.
}

export type SearchResult = {
  statisticalUnits: StatisticalUnit[];
  count: number;
};

export interface ConditionalValue {
  operator: PostgrestOperator;
  operand: string;
}

export interface SetOrder {
  type: "set_order";
  payload: { name: string};
}

export interface ResetAll {
  type: "reset_all";
}

export interface SetPage {
  type: "set_page";
  payload: {
    pageNumber: number;
  };
}

export interface SetQuery {
  type: "set_query";
  payload: {
    app_param_name: string;
    api_param_name: string;
    api_param_value: string | null;
    app_param_values: (string | null)[];
  };
}

export type SearchAction = SetQuery | ResetAll | SetOrder | SetPage;
// Define TableColumnVisibilityType with string literals
export type TableColumnVisibilityType = 'Adaptable' | 'Always';
export type ColumnProfile = "Brief" | "Regular" | "All";

export type TableColumnCode =
  | "name"
  | "activity_section"
  | "activity"
  | "top_region"
  | "region"
  | "statistic"
  | "unit_counts"
  | "sector"
  | "legal_form"
  | "data_sources"
  | "physical_address";

// Extend the base interface based on visibility type
export interface AdaptableTableColumn{
  type: 'Adaptable';
  code: TableColumnCode;
  stat_code: string | null;
  label: string;
  visible: boolean;
  profiles: ColumnProfile[];
}

export interface AlwaysTableColumn{
  type: 'Always';
  code: TableColumnCode;
  label: string;
}

// Discriminated union of all column types
export type TableColumn = AdaptableTableColumn | AlwaysTableColumn;

export type TableColumns = TableColumn[];

export type ColumnProfiles = {
  [K in ColumnProfile]: TableColumn[];
};
