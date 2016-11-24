import { createReducer } from 'redux-act'

import * as actions from './actions'

const initialState = {
  account: undefined,
}

export const editAccount = createReducer(
  {
    [actions.fetchAccountSucceeded]: (state, data) => ({
      ...state,
      account: data,
    }),
    [actions.editForm]: (state, data) => ({
      ...state,
      account: { ...state.account, [data.propName]: data.value },
    }),
  },
  initialState,
)
