import { createReducer } from 'redux-act'

import * as actions from './actions'

const initialState = {
  account: {
    name: '',
    currentPassword: '',
    email: '',
  },
}

const editAccount = createReducer(
  {
    [actions.fetchAccountSucceeded]: (state, data) => ({
      ...state,
      account: { ...initialState.account, ...data },
    }),
    [actions.editForm]: (state, data) => ({
      ...state,
      account: { ...state.account, [data.name]: data.value },
    }),
  },
  initialState,
)

export default {
  editAccount,
}
