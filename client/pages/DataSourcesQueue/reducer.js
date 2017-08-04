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
  details: {
    formData: undefined,
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

const detailsHandlers = ({
  [actions.fetchLogEntryStarted]: state => ({
    ...state,
    details: {
      formData: undefined,
      fetching: true,
      error: undefined,
    },
  }),
  [actions.fetchLogEntrySucceeded]: (state, data) => ({
    ...state,
    details: {
      formData: data,
      fetching: false,
      error: undefined,
    },
  }),
  [actions.fetchLogEntryFailed]: (state, data) => ({
    ...state,
    details: {
      formData: undefined,
      fetching: false,
      error: data,
    },
  }),
})

export default createReducer(
  {
    ...listHandlers,
    ...logHandlers,
    ...detailsHandlers,
    [actions.clear]: () => defaultState,
  },
  defaultState,
)
