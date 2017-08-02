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
  log: {
    result: [],
    totalCount: 0,
    fetching: false,
    error: undefined,
  },
}

const listHandlers = {

  [actions.fetchQueueSucceeded]: (state, data) => ({
    ...state,
    list: {
      ...state.list,
      result: data.result,
      totalCount: data.totalCount,
      fetching: false,
      error: undefined,
    },
  }),

  [actions.fetchQueueFailed]: (state, data) => ({
    ...state,
    list: {
      ...state.list,
      data: undefined,
      fetching: false,
      error: data,
    },
  }),

  [actions.fetchQueueStarted]: state => ({
    ...state,
    list: {
      ...state.list,
      fetching: true,
      error: undefined,
    },
  }),

  [actions.updateQueueFilter]: (state, data) => ({
    ...state,
    list: {
      ...state.list,
      formData: { ...state.formData, ...data },
    },
  }),

}

const logHandlers = ({

  [actions.fetchLogSucceeded]: (state, data) => ({
    ...state,
    log: {
      ...state.log,
      result: data.result,
      totalCount: data.totalCount,
      fetching: false,
      error: undefined,
    },
  }),

  [actions.fetchLogFailed]: (state, data) => ({
    ...state,
    log: {
      ...state.log,
      data: undefined,
      fetching: false,
      error: data,
    },
  }),

  [actions.fetchLogStarted]: state => ({
    ...state,
    log: {
      ...state.log,
      fetching: true,
      error: undefined,
    },
  }),

})

export default createReducer(
  {
    ...listHandlers,
    ...logHandlers,
    [actions.clear]: () => defaultState,
  },
  defaultState,
)
