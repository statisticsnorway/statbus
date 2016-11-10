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
      roles: data.result,
      totalCount: data.totalCount,
      totalPages: data.totalPages,
      status: 2,
      message: 'role fetching success',
    }),
    [actions.fetchRolesFailed]: (state, data) => ({
      ...state,
      status: -1,
      message: data,
    }),
    [actions.deleteRoleStarted]: state => ({
      ...state,
      status: 1,
      message: undefined,
    }),
    [actions.deleteRoleSucceeded]: (state, data) => ({
      ...state,
      roles: state.roles.filter(r => r.id !== data),
      totalCount: state.totalCount - 1,
      status: 0,
      message: 'role deleting success',
    }),
    [actions.deleteRoleFailed]: (state, data) => ({
      ...state,
      status: -1,
      message: data,
    }),
    [actions.fetchRoleUsersStarted]: state => ({
      ...state,
      selectedRole: undefined,
      status: 1,
      message: undefined,
    }),
    [actions.fetchRoleUsersSucceeded]: (state, data) => ({
      ...state,
      roles: state.roles.map(r => r.id === data.id ? { ...r, users: data.users } : r),
      selectedRole: data.id,
      status: 0,
      message: 'role users fetch success',
    }),
    [actions.fetchRoleUsersFailed]: (state, data) => ({
      ...state,
      selectedRole: undefined,
      status: -1,
      message: data,
    }),
  },
  {
    message: undefined,
    roles: [],
    selectedRole: undefined,
    status: 0,
    totalCount: 0,
    totalPages: 0,
  },
)
