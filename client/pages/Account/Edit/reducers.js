import { createReducer } from 'redux-act'
import * as actions from './actions'

// add account reducer
export const editAccount = createReducer(
  {
    [actions.submitAccountStarted]: state => ({
      ...state,
      status: 1,
      message: undefined,
    }),
    [actions.submitAccountSucceeded]: state => ({
      ...state,
      status: 2,
      message: 'edit account success',
    }),
    [actions.submitAccountFailed]: (state, data) => ({
      ...state,
      status: -1,
      message: data,
    }),
    [actions.fetchAccountStarted]: state => ({
      ...state,
      status: 1,
      message: undefined,
    }),
    [actions.fetchAccountSucceeded]: (state, data) => ({
      ...state,
      account: data,
      status: 2,
      message: 'account fetching success',
    }),
    [actions.fetchAccountFailed]: (state, data) => ({
      ...state,
      status: -1,
      message: data,
    }),
    [actions.editForm]: (state, data) => ({
      ...state,
      account: { ...state.account, [data.propName]: data.value },
      message: undefined,
    }),
  },
  {
    account: undefined,
    message: undefined,
    status: 0,
  },
)
