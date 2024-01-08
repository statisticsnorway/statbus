import { createReducer } from 'redux-act'

import actions from './actions.js'

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
    info: undefined,
    unit: undefined,
    type: undefined,
    properties: undefined,
    permissions: undefined,
    fetching: false,
    errors: undefined,
  },
  activitiesDetails: {
    activities: [],
    fetching: true,
    errors: undefined,
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
      formData: { ...state.list.formData, ...data },
    },
  }),

  [actions.deleteDataSourceQueueSucceeded]: (state, id) => ({
    ...state,
    list: {
      ...state.list,
      result: state.list.result.filter(x => x.id !== id),
      totalCount: state.list.totalCount - 1,
    },
  }),
}

const logHandlers = {
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

  [actions.deleteLogSucceeded]: (state, id) => ({
    ...state,
    log: {
      ...state.log,
      result: state.log.result.filter(x => x.id !== id),
      totalCount: state.log.totalCount - 1,
    },
  }),
}

const detailsHandlers = {
  [actions.fetchLogEntryStarted]: state => ({
    ...state,
    details: {
      ...defaultState.details,
      fetching: true,
      errors: undefined,
    },
  }),
  [actions.fetchLogEntrySucceeded]: (state, data) => ({
    ...state,
    details: {
      ...data,
      fetching: false,
      errors: undefined,
    },
  }),
  [actions.fetchLogEntryFailed]: (state, data) => ({
    ...state,
    details: {
      ...defaultState.details,
      fetching: false,
      errors: data,
    },
  }),
}

const activitiesDetailsHandlers = {
  [actions.fetchActivitiesDetailsSucceeded]: (state, data) => ({
    ...state,
    activitiesDetails: {
      ...state.activitiesDetails,
      fetching: false,
      activities: [...data],
    },
  }),
  [actions.fetchActivitiesDetailsFailed]: (state, data) => ({
    ...state,
    activitiesDetails: {
      ...state.activitiesDetails,
      fetching: false,
      errors: data,
    },
  }),
}

export default createReducer(
  {
    ...listHandlers,
    ...logHandlers,
    ...detailsHandlers,
    ...activitiesDetailsHandlers,
    [actions.clear]: () => defaultState,
  },
  defaultState,
)
