import { createReducer } from 'redux-act'

import * as actions from './actions.js'

const initialState = {
  roles: [],
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
    [actions.toggleRoleSucceeded]: (state, { id, status }) => ({
      ...state,
      roles: state.roles.map(x => (x.id !== id ? x : { ...x, status })),
    }),
  },
  initialState,
)

export default {
  roles,
}
