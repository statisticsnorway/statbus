const initialState = {
  statUnits: [],
  isLoading: false,
}

const reducer = (state = initialState, action) => {
  switch (action.type) {
    case 'FETCH_STATUNIT_STARTED':
      return { ...state, isLoading: true }
    case 'FETCH_STATUNIT_SUCCEEDED':
      return { ...state, statUnits: action.data, isLoading: false }
    case 'FETCH_STATUNIT_FAILED':
      return { ...state, isLoading: false }
    case 'RESTORE_STATUNIT_SUCCEEDED':
      return { ...state, statUnits: state.statUnits.filter(x => x.regId !== action.data) }
    default:
      return state
  }
}

export default reducer
