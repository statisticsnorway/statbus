import { createReducer } from 'redux-act'
import * as actions from './actions'

export const createUser = createReducer(
  {
    [actions.submitUserStarted]: state => ({
      ...state,
      status: 1,
      message: undefined,
    }),
    [actions.submitUserSucceeded]: state => ({
      ...state,
      status: 2,
      message: 'create user success',
    }),
    [actions.submitUserFailed]: (state, data) => ({
      ...state,
      status: -1,
      message: data,
    }),
  },
  {
    message: undefined,
    status: 0,
  }
)
