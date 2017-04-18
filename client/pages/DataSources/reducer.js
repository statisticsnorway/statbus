import { createReducer } from 'redux-act'

import actions from './actions'

const defaultState = {
  columns: {
    enterpriseGroup: [],
    enterpriseUnit: [],
    legalUnit: [],
    localUnit: [],
  },
  list: [],
  totalCount: 0,
}

const handlers = {

  [actions.fetchDataSourcesSucceeded]:
    (state, data) => ({
      list: data.result,
      totalCount: data.totalCount,
    }),

  [actions.fetchColumnsSucceeded]:
    (state, data) => ({
      columns: data,
    }),

}

export default createReducer(handlers, defaultState)
