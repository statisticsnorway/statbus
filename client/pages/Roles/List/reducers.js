import { createReducer } from 'redux-act'
import * as actions from './actions'

export const roles = createReducer(
  {
    [actions.fetchRolesStarted]: state => ({
      ...state,
      status: 1,
      message: undefined,
    }),
    [actions.fetchRolesSucceeded]: (state, data) => ({
      ...state,
      roles: data,
      status: 2,
      message: undefined,
    }),
    [actions.fetchRolesFailed]: (state, data) => ({
      ...state,
      status: -1,
      message: data,
    }),
  },
  {
    message: undefined,
    roles: [],
    status: 0,
  }
)
