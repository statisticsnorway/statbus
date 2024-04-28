import { createReducer } from 'redux-act'

import * as actions from './actions.js'

const initialState = {
  filter: undefined,
}

const viewLinks = createReducer(
  {
    [actions.linkSearchStarted]: (state, filter) => ({
      ...state,
      filter,
    }),
    [actions.clear]: () => initialState,
  },
  initialState,
)

export default {
  viewLinks,
}
