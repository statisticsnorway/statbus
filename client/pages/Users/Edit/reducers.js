import { createReducer } from 'redux-act'
import * as actions from './actions'

// add user reducer
export const editUser = createReducer(
  {
    [actions.submitUserStarted]: state => ({
      ...state,
      status: 1,
      message: undefined,
    }),
    [actions.submitUserSucceeded]: state => ({
      ...state,
      status: 2,
      message: undefined,
    }),
    [actions.submitUserFailed]: (state, data) => ({
      ...state,
      status: -1,
      message: data
    }),
    [actions.fetchUserStarted]: state => ({
      ...state,
      status: 1,
      message: undefined,
    }),
    [actions.fetchUserSucceeded]: (state, data) => ({
      ...state,
      user: data,
      status: 2,
      message: undefined,
    }),
    [actions.fetchUserFailed]: state => ({
      ...state,
      status: -1,
      message: data,
    }),
    [actions.editForm]: (state, data) => ({
      ...state,
      user: { ...state.user, [data.propName]: data.value },
      message: undefined,
    })
  },
  {
    user: undefined,
    message: undefined,
    status: 0,
  }
)
