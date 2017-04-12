import { createAction, createReducer } from 'redux-act'

export const showNotification = createAction('show notification')
export const hideNotification = createAction('hide notification')

const initialState = {
  title: undefined,
  body: '',
  onConfirm: _ => _,
  onCancel: _ => _,
  open: false,
}

export const reducer = createReducer(
  {
    [showNotification]: (state, data) => ({
      ...state,
      ...data,
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
