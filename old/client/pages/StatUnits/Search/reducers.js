import { createReducer } from 'redux-act'

import * as actions from './actions.js'
import { updateFilter } from '../actions.js'

const initialState = {
  formData: { sortRule: 1 },
  isLoading: false,
  lookups: { 5: [] },
  error: undefined,
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
    [actions.clear]: state => ({
      ...state,
      ...initialState,
    }),
    [actions.fetchDataStateChanged]: (state, data) => ({
      ...state,
      isLoading: data,
    }),
    [actions.deleteStatUnitSuccessed]: (state, data) => ({
      ...state,
      statUnits: state.statUnits.filter((val, i) => i !== data.index),
      totalCount: state.totalCount - 1,
    }),
    [actions.fetchLookupSucceeded]: (state, data) => ({
      ...state,
      lookups: {
        ...state.lookups,
        [data.id]: data.lookup,
      },
    }),

    [actions.fetchDataFailed]: (state, message) => ({
      ...state,
      error: message,
      isLoading: false,
    }),
    [actions.clearError]: state => ({
      ...state,
      error: undefined,
    }),
    [actions.setSearchCondition]: (state, condition) => ({
      ...state,
      formData: {
        ...state.formData,
        comparison: condition,
      },
    }),
  },
  initialState,
)

export default {
  statUnits,
}
