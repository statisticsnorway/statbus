import { createReducer } from 'redux-act'

import * as actions from './actions.js'

const initialState = {
  role: undefined,
}

const editRole = createReducer(
  {
    [actions.fetchRoleSucceeded]: (state, data) => ({
      ...state,
      role: data,
    }),
    [actions.editForm]: (state, data) => ({
      ...state,
      role: { ...state.role, [data.name]: data.value },
    }),
  },
  initialState,
)

export default {
  editRole,
}
