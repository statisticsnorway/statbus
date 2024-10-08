import { SearchAction, SearchOrder, SearchState } from "./search";

export function searchFilterReducer(
  state: SearchState,
  action: SearchAction
): SearchState {
  switch (action.type) {
    case "set_query": {
      const {
        app_param_name,
        api_param_name,
        api_param_value,
        app_param_values,
      } = action.payload;
      return {
        ...state,
        queries: { ...state.queries, [api_param_name]: api_param_value },
        values: { ...state.values, [app_param_name]: app_param_values },
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
      const validDirections: Set<'asc' | 'desc'> = new Set(['asc', 'desc']);
      const currentDirection = state.order.direction;
      const direction: 'asc' | 'desc' = validDirections.has(currentDirection as 'asc' | 'desc') ? (currentDirection === 'desc' ? 'asc' : 'desc') : 'desc';

      const order: SearchOrder = name === state.order.name
        ? { ...state.order, direction }
        : { name, direction: 'desc' };
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
