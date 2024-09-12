type SearchFilterOption = {
  readonly label: string;
  readonly value: string | null;
  readonly humanReadableValue?: string;
  readonly className?: string;
};

type SearchOrder = {
  readonly name: string;
  readonly direction: string;
};

type SearchPagination = {
  readonly pageSize: number;
  readonly pageNumber: number;
};

interface SearchState {
  readonly queries: Record<string, string | null>;
  readonly values: Record<string, (string | null)[] | undefined>;
  readonly order: SearchOrder;
  readonly pagination: SearchPagination;
}

type SearchResult = {
  statisticalUnits: Tables<"statistical_unit">[];
  count: number;
};

interface ConditionalValue {
  operator: PostgrestOperator;
  value: string;
}

interface SetOrder {
  type: "set_order";
  payload: {
    name: string;
  };
}

interface ResetAll {
  type: "reset_all";
}

interface SetPage {
  type: "set_page";
  payload: {
    pageNumber: number;
  };
}

interface SetQuery {
  type: "set_query";
  payload: {
    app_param_name: string;
    api_param_name: string;
    api_param_value: string | null;
    app_param_values: (string | null)[];
  };
}

type SearchAction = SetQuery | ResetAll | SetOrder | SetPage;
