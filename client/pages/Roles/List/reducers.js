import { createReducer } from 'redux-act'

import * as actions from './actions'

const initialState = {
  roles: [],
  selectedRole: undefined,
  totalCount: 0,
  totalPages: 0,
}

const roles = createReducer(
  {
    [actions.fetchRolesSucceeded]: (state, data) => ({
      ...state,
      roles: data.result,
      totalCount: data.totalCount,
      totalPages: data.totalPages,
    }),
    [actions.deleteRoleSucceeded]: (state, data) => ({
      ...state,
      roles: state.roles.filter(r => r.id !== data),
      totalCount: state.totalCount - 1,
    }),
    [actions.fetchRoleUsersStarted]: state => ({
      ...state,
      selectedRole: undefined,
    }),
    [actions.fetchRoleUsersSucceeded]: (state, data) => ({
      ...state,
      roles: state.roles.map(r => r.id === data.id ? { ...r, users: data.users } : r),
      selectedRole: data.id,
    }),
    [actions.fetchRoleUsersFailed]: state => ({
      ...state,
      selectedRole: undefined,
    }),
  },
  initialState,
)

export default {
  roles,
}
