import { createReducer } from 'redux-act'

import { request as actions } from 'helpers/actionCreators'

const defaultState = []
const handlers = {
  [actions.started]: (state, data) => [
    ...state,
    {
      id: data.id,
      code: 1,
      message: data.message || 'RequestStarted',
    },
  ],
  [actions.succeeded]: (state, data) => [
    ...state,
    {
      id: data.id,
      code: 2,
      message: data.message || 'RequestSucceeded',
    },
  ],
  [actions.failed]: (state, data) => [
    ...state,
    {
      id: data.id,
      code: -1,
      message: data.message || 'RequestFailed',
    },
  ],
  [actions.dismiss]: (state, data) => state.filter(x => x.id !== data),
  [actions.dismissAll]: () => defaultState,
}

export default createReducer(handlers, defaultState)
