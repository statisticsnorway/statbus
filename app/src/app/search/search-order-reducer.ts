import {SearchOrder, SetOrderAction} from "@/app/search/search.types";

export function searchOrderReducer(state: SearchOrder, action: SetOrderAction): SearchOrder {
  switch (action.type) {
    case "set_order": {
      const {name} = action.payload
      return name == state.name
        ? {...state, direction: state.direction === "desc.nullslast" ? "asc" : "desc.nullslast"}
        : {name, direction: "desc.nullslast"}
    }
    default:
      return state
  }
}
