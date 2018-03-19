import { createReducer } from 'redux-act'

import * as actions from './actions'
import { updateFilter } from '../actions'

const initialState = {
  formData: {
    sortRule: 1,
  },
  statUnits: [],
  totalCount: 0,
  isLoading: false,
  lookups: { 5: [] },
}

const statUnits = createReducer(
  {
    [updateFilter]: (state, data) => ({
      ...state,
      formData: {
        ...state.formData,
        ...data,
      },
    }),

    [actions.fetchDataSucceeded]: (state, { result, totalCount }) => ({
      ...state,
      statUnits: result,
      totalCount,
    }),
    [actions.clear]: () => initialState,
    [actions.fetchDataStateChanged]: (state, data) => ({
      ...state,
      isLoading: data,
    }),
    [actions.fetchLookupSucceeded]: (state, data) => ({
      ...state,
      lookups: {
        ...state.lookups,
        [data.id]: data.lookup,
      },
    }),
  },
  initialState,
)

export default {
  statUnits,
}
