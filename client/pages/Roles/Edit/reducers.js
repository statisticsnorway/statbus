import { createReducer } from 'redux-act'

import * as actions from './actions'

const initialState = {
  role: undefined,
}

// add role reducer
export const editRole = createReducer(
  {
    [actions.fetchRoleSucceeded]: (state, data) => ({
      ...state,
      role: data,
    }),
    [actions.editForm]: (state, data) => ({
      ...state,
      role: { ...state.role, [data.propName]: data.value },
    }),
  },
  initialState,
)
