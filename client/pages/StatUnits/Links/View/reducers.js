import { createReducer } from 'redux-act'

import * as actions from './actions'

const initialState = {
  filter: undefined,
  links: [],
  units: [],
  isLoading: false,
}

const viewLinks = createReducer(
  {
    [actions.linkSearchStarted]: (state, filter) => ({
      ...state,
      filter,
      links: [],
      units: [],
      isLoading: true,
    }),
    [actions.linkSearchSuccess]: (state, response) => ({
      ...state,
      isLoading: false,
      units: response,
      links: [],
    }),
    [actions.linkSearchFailed]: state => ({
      ...state,
      isLoading: false,
    }),
  },
  initialState,
)

export default {
  viewLinks,
}
