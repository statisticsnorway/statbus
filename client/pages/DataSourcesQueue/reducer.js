import { createReducer } from 'redux-act'

import actions from './actions'

const defaultState = {
  list: {
    formData: {},
    result: [],
    totalCount: 0,
    fetching: false,
    error: undefined,
  },
}

const handlers = {

  [actions.fetchDataSucceeded]: (state, data) => ({
    ...state,
    list: {
      ...state.list,
      result: data.result,
      totalCount: data.totalCount,
      fetching: false,
      error: undefined,
    },
  }),

  [actions.fetchDataFailed]: (state, data) => ({
    ...state,
    list: {
      ...state.list,
      data: undefined,
      fetching: false,
      error: data,
    },
  }),

  [actions.fetchDataStarted]: state => ({
    ...state,
    list: {
      ...state.list,
      fetching: true,
      error: undefined,
    },
  }),

  [actions.updateFilter]: (state, data) => ({
    ...state,
    list: {
      ...state.list,
      formData: { ...state.formData, ...data },
    },
  }),

  [actions.clear]: () => defaultState,

}

export default createReducer(handlers, defaultState)
