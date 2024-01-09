import { createReducer } from 'redux-act'

import * as actions from './actions.js'

const initialState = {
  links: [],
  isLoading: false,
}

const deleteLinks = createReducer(
  {
    [actions.linkDeleteStarted]: state => ({
      ...state,
      isLoading: true,
    }),
    [actions.linkDeleteSuccess]: state => ({
      ...state,
      isLoading: false,
      links: [],
    }),
    [actions.linkDeleteFailed]: state => ({
      ...state,
      isLoading: false,
    }),
  },
  initialState,
)

export default {
  deleteLinks,
}
