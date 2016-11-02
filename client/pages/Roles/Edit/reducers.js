import { createReducer } from 'redux-act'
import * as actions from './actions'

// add role reducer
export const editRole = createReducer(
  {
    [actions.submitRoleStarted]: state => ({
      ...state,
      status: 1,
      message: undefined,
    }),
    [actions.submitRoleSucceeded]: state => ({
      ...state,
      status: 2,
      message: 'edit role success',
    }),
    [actions.submitRoleFailed]: (state, data) => ({
      ...state,
      status: -1,
      message: data,
    }),
    [actions.fetchRoleStarted]: state => ({
      ...state,
      status: 1,
      message: undefined,
    }),
    [actions.fetchRoleSucceeded]: (state, data) => ({
      ...state,
      role: data,
      status: 2,
      message: 'role fetching success',
    }),
    [actions.fetchRoleFailed]: (state, data) => ({
      ...state,
      status: -1,
      message: data,
    }),
    [actions.editForm]: (state, data) => ({
      ...state,
      role: { ...state.role, [data.propName]: data.value },
      message: undefined,
    }),
  },
  {
    role: undefined,
    message: undefined,
    status: 0,
  }
)
