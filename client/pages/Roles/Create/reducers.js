import { createReducer } from 'redux-act'
import * as actions from './actions'

export const createRole = createReducer(
  {
    [actions.submitRoleStarted]: state => ({
      ...state,
      status: 1,
      message: undefined,
    }),
    [actions.submitRoleSucceeded]: state => ({
      ...state,
      status: 2,
      message: 'create role success',
    }),
    [actions.submitRoleFailed]: (state, data) => ({
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
