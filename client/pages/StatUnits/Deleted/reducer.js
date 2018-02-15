import { createReducer } from 'redux-act'

import * as actions from './actions'
import { updateFilter } from '../actions'

const defaultState = {
  formData: {},
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

  [actions.fetchDataStarted]: state => ({
    ...state,
    isLoading: true,
  }),
}

export default createReducer(handlers, defaultState)
