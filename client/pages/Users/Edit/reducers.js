import { createReducer } from 'redux-act'

import * as actions from './actions'

const initialState = {
  user: undefined,
}

export const editUser = createReducer(
  {
    [actions.fetchUserSucceeded]: (state, data) => ({
      ...state,
      user: data,
    }),
    [actions.editForm]: (state, data) => ({
      ...state,
      user: { ...state.user, [data.propName]: data.value },
    }),
  },
  initialState,
)
