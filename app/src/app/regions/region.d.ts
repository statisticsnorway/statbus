type RegionPagination = {
  readonly pageSize: number;
  readonly pageNumber: number;
};
type RegionOrder = {
  readonly name: string;
  readonly direction: string;
};
interface RegionState {
  readonly queries: Record<string, string | null>;
  readonly values: Record<string, (string | null)[] | undefined>;
  readonly order: RegionOrder;
  readonly pagination: RegionPagination;
}

type RegionResult = {
  regions: Tables<"region">[];
  count: number;
};

interface SetOrder {
  type: "set_order";
  payload: {
    name: string;
  };
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
    name: string;
    query: string | null;
    values: (string | null)[];
  };
}

interface ResetSearch {
  type: "reset_search";
}

type RegionAction = SetQuery | SetOrder | ResetSearch | SetPage;
