import { createReducer } from 'redux-act'

import * as actions from './actions'
import { updateFilter } from '../actions'

const defaultState = {
  formData: {},
  statUnits: [],
  totalCount: 0,
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
  }),
}

export default createReducer(handlers, defaultState)
