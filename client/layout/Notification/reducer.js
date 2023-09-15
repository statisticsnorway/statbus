import { createReducer } from 'redux-act'
import R from 'ramda'

import { notification as actions } from '/client/helpers/actionCreators'

const defaultState = {
  title: undefined,
  body: '',
  onConfirm: R.identity,
  onCancel: R.identity,
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
