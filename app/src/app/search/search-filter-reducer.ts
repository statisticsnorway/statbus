import { SearchAction, SearchOrder } from "./search.d";

export const defaultOrder: SearchOrder = {field: "name", direction: "asc"};

export function modifySearchStateReducer(
  state: any,
  action: SearchAction
): any {
  switch (action.type) {
    case "set_query": {
      const {
        app_param_name,
        api_param_name,
        api_param_value,
        app_param_values,
      } = action.payload;
      // This reducer is now obsolete due to the Jotai refactor.
      // The logic has been moved into the granular `useSearch...` hooks
      // and the `useSearchUrlSync` hook. This function is no longer called
      // but is kept to satisfy type dependencies until the old search provider
      // is fully removed.
      return state;
    }
    case "reset_all":
       // See comment in "set_query"
      return state;
    case "set_order": {
       // See comment in "set_query"
      return state;
    }
    case "set_page": {
       // See comment in "set_query"
      return state;
    }
    default:
      return state;
  }
}
