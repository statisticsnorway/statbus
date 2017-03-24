import { createAction, createReducer } from 'redux-act'

export const showNotification = createAction('show notification')
export const hideNotification = createAction('hide notification')

const initialState = {
  text: '',
  open: false,
}

export const reducer = createReducer(
  {
    [showNotification]: (state, data) => ({
      ...state,
      text: data,
      open: true,
    }),
    [hideNotification]: state => ({
      ...state,
      open: false,
    }),
  },
  initialState,
)

export const actions = {
  showNotification,
  hideNotification,
}
