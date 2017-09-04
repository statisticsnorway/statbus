import { createReducer } from 'redux-act'

import { notification as actions } from 'helpers/actionCreators'

const stubF = () => { }

const defaultState = {
  title: undefined,
  body: '',
  onConfirm: stubF,
  onCancel: stubF,
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
