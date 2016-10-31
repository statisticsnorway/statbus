import { createReducer } from 'redux-act'
import * as actions from './actions'

// add role reducer
export const editRole = createReducer(
  {
    [actions.editRoleStarted]: state => ({
      ...state,
      status: 1,
      message: undefined,
    }),
    [actions.editRoleSucceeded]: state => ({
      ...state,
      status: 2,
      message: undefined,
    }),
    [actions.editRoleFailed]: (state, data) => ({
      ...state,
      status: -1,
      message: data
    }),
  },
  {
    message: undefined,
    status: 0,
  }
)
