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
  },
  initialState,
)

export default {
  roles,
}
