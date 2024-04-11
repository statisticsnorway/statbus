export function searchFilterReducer(
  state: SearchState,
  action: SearchAction
): SearchState {
  switch (action.type) {
    case "set_query": {
      const { name, query, values } = action.payload;
      return {
        ...state,
        queries: { ...state.queries, [name]: query },
        values: { ...state.values, [name]: values },
        pagination: { ...state.pagination, pageNumber: 1 },
      };
    }
    case "reset_all":
      return {
        ...state,
        queries: {},
        values: {},
        pagination: { ...state.pagination, pageNumber: 1 },
      };
    case "set_order": {
      const { name } = action.payload;
      const order =
        name == state.order.name
          ? {
              ...state.order,
              direction:
                state.order.direction === "desc.nullslast"
                  ? "asc"
                  : "desc.nullslast",
            }
          : { name, direction: "desc.nullslast" };
      return { ...state, order };
    }
    case "set_page": {
      const { pageNumber } = action.payload;
      const pagination = { ...state.pagination, pageNumber };
      return { ...state, pagination };
    }
    default:
      return state;
  }
}
