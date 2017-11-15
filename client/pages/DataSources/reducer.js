import { createReducer } from 'redux-act'

import actions, { clear } from './actions'

const defaultState = {
  columns: {
    enterpriseGroup: [],
    enterpriseUnit: [],
    legalUnit: [],
    localUnit: [],
  },
  searchForm: {},
  list: [],
  dsList: [],
  totalCount: 0,
  editFormData: {},
}

const handlers = {
  [actions.fetchDataSourcesSucceeded]: (state, data) => ({
    ...state,
    list: data.result,
    totalCount: data.totalCount,
  }),

  [actions.fetchDataSourceSucceeded]: (state, data) => ({
    ...state,
    editFormData: data,
  }),

  [actions.fetchDataSourcesListSucceeded]: (state, data) => ({
    ...state,
    dsList: data.result,
  }),

  [actions.uploadFileSucceeded]: state => ({
    ...state,
  }),

  [actions.uploadFileError]: state => ({
    ...state,
  }),

  [actions.fetchColumnsSucceeded]: (state, data) => ({
    ...state,
    columns: data,
  }),

  [actions.updateFilter]: (state, data) => ({
    ...state,
    searchForm: { ...state.searchForm, ...data },
  }),

  [clear]: () => defaultState,
}

export default createReducer(handlers, defaultState)
