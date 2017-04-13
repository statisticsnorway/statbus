import { createReducer } from 'redux-act'

import actions from './actions'

const defaultState = {
  items: [],
  totalCount: 0,
}

const handlers = {
  [actions.fetchDataSourcesSucceeded]:
    (state, data) => ({
      items: data.result,
      totalCount: data.totalCount,
    }),
}

export default createReducer(handlers, defaultState)
