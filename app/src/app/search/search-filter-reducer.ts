import { SearchAction, SearchOrder, SearchState } from "./search";

export const defaultOrder = {name: "name", direction: "asc"} as SearchOrder;

export function modifySearchStateReducer(
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
      const resetPage =
        state.apiSearchParams[api_param_name] !== api_param_value;
      return {
        ...state,
        apiSearchParams: {
          ...state.apiSearchParams,
          [api_param_name]: api_param_value,
        },
        appSearchParams: {
          ...state.appSearchParams,
          [app_param_name]: app_param_values,
        },
        pagination: {
          ...state.pagination,
          pageNumber: resetPage ? 1 : state.pagination.pageNumber,
        },
      };

    }
    case "reset_all":
      return {
        ...state,
        apiSearchParams: {},
        appSearchParams: {},
        pagination: { ...state.pagination, pageNumber: 1 },
        order: defaultOrder
      };
    case "set_order": {
      const name = action.payload.name;
      const flippedDirection = state.order.direction === 'desc' ? 'asc' : 'desc';

      const order: SearchOrder = name === state.order.name
        ? { ...state.order, direction: flippedDirection }
        : { name, direction: 'asc' };
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
