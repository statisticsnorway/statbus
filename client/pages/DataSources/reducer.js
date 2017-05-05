import { createReducer } from 'redux-act'

import actions from './actions'

const defaultState = {
  columns: {
    enterpriseGroup: [],
    enterpriseUnit: [],
    legalUnit: [],
    localUnit: [],
  },
  searchForm: {},
  list: [],
  totalCount: 0,
}

const handlers = {

  [actions.fetchDataSourcesSucceeded]:
    (state, data) => ({
      ...state,
      list: data.result,
      totalCount: data.totalCount,
    }),

  [actions.fetchColumnsSucceeded]:
    (state, data) => ({
      ...state,
      columns: data,
    }),

  [actions.updateFilter]:
    (state, data) => ({
      ...state,
      searchForm: { ...state.searchForm, ...data },
    }),

}

export default createReducer(handlers, defaultState)
