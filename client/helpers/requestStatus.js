import getUid from './getUid'

const ADD_STARTED_REQUEST = 'ADD_STARTED_REQUEST'
const ADD_SUCCEEDED_REQUEST = 'ADD_SUCCEEDED_REQUEST'
const ADD_FAILED_REQUEST = 'ADD_FAILED_REQUEST'
const DISMISS_SPECIFIED_MESSAGE = 'DISMISS_SPECIFIED_MESSAGE'
const DISMISS_ALL_MESSAGES = 'DISMISS_ALL_MESSAGES'

export const actions = {
  started: data => ({
    type: ADD_STARTED_REQUEST,
    data: {
      ...data,
      id: getUid(),
    },
  }),
  succeeded: data => ({
    type: ADD_SUCCEEDED_REQUEST,
    data: {
      ...data,
      id: getUid(),
    },
  }),
  failed: data => ({
    type: ADD_FAILED_REQUEST,
    data: {
      ...data,
      id: getUid(),
    },
  }),
  dismiss: id => ({
    type: DISMISS_SPECIFIED_MESSAGE,
    data: id,
  }),
  dismissAll: () => ({
    type: DISMISS_ALL_MESSAGES,
  }),
}

export const reducer = (state = [], action) => {
  switch (action.type) {
    case ADD_STARTED_REQUEST:
      return [
        ...state,
        {
          id: action.data.id,
          code: 1,
          message: action.data.message || 'RequestStarted',
        },
      ]
    case ADD_SUCCEEDED_REQUEST:
      return [
        ...state,
        {
          id: action.data.id,
          code: 2,
          message: action.data.message || 'RequestSucceeded',
        },
      ]
    case ADD_FAILED_REQUEST:
      return [
        ...state,
        {
          id: action.data.id,
          code: -1,
          message: action.data.message || 'RequestFailed',
        },
      ]
    case DISMISS_SPECIFIED_MESSAGE:
      return state.filter(x => x.id !== action.data)
    case DISMISS_ALL_MESSAGES:
      return []
    default:
      return state
  }
}
