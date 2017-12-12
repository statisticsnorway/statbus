import { createReducer } from 'redux-act'
import { toUtc } from 'helpers/dateHelper'

import actions from './actions'

const defaultState = {
  queue: {
    formData: {},
    items: [],
    totalCount: 0,
    fetching: false,
    error: undefined,
  },
  create: {
    item: {
      dateFrom: toUtc(new Date()),
      dateTo: toUtc(new Date()),
      comment: '',
    },
  },
}

const queueHandlers = {
  [actions.fetchQueueSucceeded]: (state, data) => ({
    ...state,
    queue: {
      ...state.queue,
      items: data.items,
      totalCount: data.totalCount,
      fetching: false,
      error: undefined,
    },
  }),

  [actions.fetchQueueFailed]: (state, data) => ({
    ...state,
    queue: {
      ...state.queue,
      data: undefined,
      fetching: false,
      error: data,
    },
  }),

  [actions.fetchQueueStarted]: state => ({
    ...state,
    queue: {
      ...state.queue,
      fetching: true,
      error: undefined,
    },
  }),

  [actions.updateQueueFilter]: (state, data) => ({
    ...state,
    queue: {
      ...state.queue,
      formData: { ...state.formData, ...data },
    },
  }),

  [actions.editQueueItem]: (state, data) => ({
    ...state,
    create: {
      ...state.create,
      item: {
        ...state.create.item,
        [data.name]: data.value,
      },
    },
  }),
}

export default createReducer(
  {
    ...queueHandlers,
    [actions.clear]: () => defaultState,
  },
  defaultState,
)
