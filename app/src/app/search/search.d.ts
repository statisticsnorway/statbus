type PostgrestOperator = "eq" | "gt" | "lt" | "in";

type SearchFilterName =
  | "search"
  | "tax_ident"
  | "unit_type"
  | "physical_region_path"
  | "primary_activity_category_path"
  | "sector_code"
  | "legal_form_code"
  | "invalid_codes";

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
  readonly filters: SearchFilter[];
  readonly order: SearchOrder;
  readonly pagination: SearchPagination;
}

type SearchFilter = {
  readonly type: "options" | "radio" | "conditional" | "search";
  readonly name: SearchFilterName;
  readonly label: string;
  readonly options?: SearchFilterOption[];
  readonly selected: (string | null)[];
  readonly operator?: PostgrestOperator;
};

type SearchResult = {
  statisticalUnits: Tables<"statistical_unit">[];
  count: number;
};

interface ConditionalValue {
  operator: PostgrestOperator;
  value: string;
}

interface ToggleOption {
  type: "toggle_option";
  payload: {
    name: string;
    value: string | null;
  };
}

interface SetOrder {
  type: "set_order";
  payload: {
    name: string;
  };
}

interface ToggleRadioOption {
  type: "toggle_radio_option";
  payload: {
    name: string;
    value: string | null;
  };
}

interface SetCondition {
  type: "set_condition";
  payload: {
    name: string;
    value: string;
    operator: PostgrestOperator;
  };
}

interface SetSearch {
  type: "set_search";
  payload: {
    name: string;
    value: string;
  };
}

interface Reset {
  type: "reset";
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

type SearchAction =
  | ToggleOption
  | ToggleRadioOption
  | SetCondition
  | SetSearch
  | Reset
  | ResetAll
  | SetOrder
  | SetPage;

interface FilterOptions {
  activityCategories: Tables<"activity_category_available">[];
  regions: Tables<"region_used">[];
  statisticalVariables: Tables<"stat_definition">[];
  sectors: Tables<"sector">[];
  legalForms: Tables<"legal_form">[];
}

type SetOrderAction = { type: "set_order"; payload: { name: string } };
