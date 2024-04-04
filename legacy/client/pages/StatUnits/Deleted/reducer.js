import { createReducer } from 'redux-act'

import * as actions from './actions.js'
import { updateFilter } from '../actions.js'

const defaultState = {
  formData: { sortRule: 1 },
  statUnits: [],
  totalCount: 0,
  isLoading: false,
}

const handlers = {
  [updateFilter]: (state, data) => ({
    ...state,
    formData: { ...state.formData, ...data },
  }),

  [actions.fetchDataSucceeded]: (state, { result, totalCount }) => ({
    ...state,
    statUnits: result,
    totalCount,
    isLoading: false,
  }),
  [actions.restoreSucceeded]: (state, data) => ({
    ...state,
    statUnits: state.statUnits.filter((val, i) => i !== data.index),
  }),
  [actions.fetchDataStarted]: state => ({
    ...state,
    isLoading: true,
  }),
  [actions.setSearchConditionForDeleted]: (state, condition) => ({
    ...state,
    formData: {
      ...state.formData,
      comparison: condition,
    },
  }),
  [actions.clearSearchFormForDeleted]: () => defaultState,
}

export default createReducer(handlers, defaultState)
