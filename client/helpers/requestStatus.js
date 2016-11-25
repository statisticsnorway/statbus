import { createAction, createReducer } from 'redux-act'

export const actions = {
  dismiss: createAction('REQUEST_DISMISS'),
  failed: createAction('REQUEST_FAILED'),
  started: createAction('REQUEST_STARTED'),
  succeeded: createAction('REQUEST_SUCCEEDED'),
}

const initialState = {
  messages: undefined,
  code: 0,
}

export const reducer = createReducer(
  {
    [actions.dismiss]: () => initialState,
    [actions.failed]: (state, data) => ({
      code: -1,
      messages: data && data.length > 0 ? data : ['request failed'],
    }),
    [actions.started]: (state, data) => ({
      code: 1,
      messages: data && data.length > 0 ? data : ['request started'],
    }),
    [actions.succeeded]: (state, data) => ({
      code: 2,
      messages: data && data.length > 0 ? data : ['request succeeded'],
    }),
  },
  initialState,
)
