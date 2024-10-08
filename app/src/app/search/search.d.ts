import { TimeContext } from "../types";

export type SearchFilterOption = {
  readonly label: string;
  readonly value: string | null;
  readonly humanReadableValue?: string;
  readonly className?: string;
};

export type SearchOrder = {
  readonly name: string;
  readonly direction: "asc" | "desc";
};

export type SearchPagination = {
  readonly pageSize: number;
  readonly pageNumber: number;
};

export interface SearchState {
  readonly queries: Record<string, string | null>;
  readonly values: Record<string, (string | null)[] | undefined>;
  readonly order: SearchOrder;
  readonly pagination: SearchPagination;
  readonly timeContext: TimeContext | null;
}

export type SearchResult = {
  statisticalUnits: Tables<"statistical_unit">[];
  count: number;
};

export interface ConditionalValue {
  operator: PostgrestOperator;
  value: string;
}

export interface SetOrder {
  type: "set_order";
  payload: {
    name: string;
  };
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
