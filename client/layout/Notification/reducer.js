import { createReducer } from 'redux-act'

import { notification as actions } from 'helpers/actionCreators'

const defaultState = {
  title: undefined,
  body: '',
  onConfirm: _ => _,
  onCancel: _ => _,
  open: false,
}

const handlers = {
  [actions.showNotification]: (state, data) => ({
    ...state,
    ...data,
    open: true,
  }),
  [actions.hideNotification]: state => ({
    ...state,
    open: false,
  }),
}

export default createReducer(handlers, defaultState)
