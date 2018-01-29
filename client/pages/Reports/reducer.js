import { createReducer } from 'redux-act'

import * as actions from './actions'

const defaultState = {
  reportsTree: undefined,
}

const handlers = {
  [actions.fetchReportsTreeSucceeded]: (state, data) => ({
    ...state,
    reportsTree: data,
  }),
}

export default createReducer(handlers, defaultState)
