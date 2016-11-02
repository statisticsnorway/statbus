import { createReducer } from 'redux-act'
import * as actions from './actions'

export const users = createReducer(
  {
    [actions.fetchUsersStarted]: state => ({
      ...state,
      status: 1,
      message: undefined,
    }),
    [actions.fetchUsersSucceeded]: (state, data) => ({
      ...state,
      users: data.result,
      totalCount: data.totalCount,
      totalPages: data.totalPages,
      status: 2,
      message: 'fetch users success',
    }),
    [actions.fetchUsersFailed]: (state, data) => ({
      ...state,
      status: -1,
      message: data,
    }),
    [actions.deleteUserStarted]: state => ({
      ...state,
      status: 1,
      message: undefined,
    }),
    [actions.deleteUserSucceeded]: (state, data) => ({
      ...state,
      users: state.users.filter(r => r.id !== data),
      totalCount: state.totalCount - 1,
      status: 0,
      message: 'delete user success',
    }),
    [actions.deleteUserFailed]: (state, data) => ({
      ...state,
      status: -1,
      message: data,
    }),
  },
  {
    message: undefined,
    users: [],
    status: 0,
    totalCount: 0,
    totalPages: 0,
  }
)
