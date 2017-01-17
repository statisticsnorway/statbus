import { createReducer } from 'redux-act'

import * as actions from './actions'

const users = createReducer(
  {
    [actions.fetchUsersSucceeded]: (state, data) => ({
      ...state,
      users: data.result,
      totalCount: data.totalCount,
      totalPages: data.totalPages,
    }),
    [actions.deleteUserSucceeded]: (state, data) => ({
      ...state,
      users: state.users.filter(r => r.id !== data),
      totalCount: state.totalCount - 1,
    }),
  },
  {
    users: [],
    totalCount: 0,
    totalPages: 0,
  },
)

export default {
  users,
}
