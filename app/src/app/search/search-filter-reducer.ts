export function searchFilterReducer(state: SearchState, action: SearchAction): SearchState {
  switch (action.type) {
    case "toggle_option": {
      const {name, value} = action.payload
      const filters = state.filters.map(f =>
        f.name === name ? {
          ...f,
          selected: f.selected.includes(value) ? f.selected.filter(id => id !== value) : [...f.selected, value]
        } : f
      )
      return {...state, filters, pagination: { ...state.pagination, pageNumber: 1 }}
    }
    case "toggle_radio_option": {
      const {name, value} = action.payload
      const filters = state.filters.map(f =>
        f.name === name ? {...f, selected: f.selected.find(id => id == value) ? [] : [value]} : f)
      return {...state, filters, pagination: { ...state.pagination, pageNumber: 1 }}
    }
    case "set_condition": {
      const {name, value, condition} = action.payload
      const filters = state.filters.map(f => f.name === name ? {...f, selected: [value], condition} : f)
      return {...state, filters, pagination: { ...state.pagination, pageNumber: 1 }}
    }
    case "set_search": {
      const {name, value} = action.payload
      const filters = state.filters.map(f => f.name === name ? {...f, selected: [value]} : f)
      return {...state, filters, pagination: { ...state.pagination, pageNumber: 1 }}
    }
    case "reset": {
      const {name} = action.payload
      const filters = state.filters.map(f => f.name === name ? {...f, selected: []} : f)
      return {...state, filters, pagination: { ...state.pagination, pageNumber: 1 }}
    }
    case "reset_all":
      const filters = state.filters.map(f => ({...f, selected: []}))
      return {...state, filters, pagination: { ...state.pagination, pageNumber: 1 }}
    case "set_order": {
      const {name} = action.payload
      const order = name == state.order.name
        ? {...state.order, direction: state.order.direction === "desc.nullslast" ? "asc" : "desc.nullslast"}
        : {name, direction: "desc.nullslast"}
      return {...state, order}
    }
    case "set_page": {
      const { pageNumber} = action.payload;
      const pagination = { ...state.pagination, pageNumber }
      return { ...state, pagination };
    }
    default:
      return state
  }
}
