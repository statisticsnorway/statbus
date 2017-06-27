import { createReducer } from 'redux-act'

import * as actions from './actions'

const initialState = {
  filter: undefined,
}

const viewOrgLinks = createReducer(
  {
    [actions.orgLinkSearchStarted]: (state, filter) => ({
      ...state,
      filter,
    }),
  },
  initialState,
)

export default {
  viewOrgLinks,
}
