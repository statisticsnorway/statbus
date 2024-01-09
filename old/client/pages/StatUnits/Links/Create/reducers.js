import { createReducer } from 'redux-act'

import * as actions from './actions.js'

const initialState = {
  links: [],
  isLoading: false,
}

const editLinks = createReducer(
  {
    [actions.linkCreateStarted]: state => ({
      ...state,
      isLoading: true,
    }),
    [actions.linkCreateSuccess]: (state, data) => ({
      ...state,
      isLoading: false,
      links: [data, ...state.links],
    }),
    [actions.linkCreateFailed]: state => ({
      ...state,
      isLoading: false,
    }),
    [actions.linkDeleteSuccess]: (state, data) => ({
      ...state,
      links: state.links.filter(v =>
        v.source1.id !== data.source1.id ||
          v.source1.type !== data.source1.type ||
          v.source2.id !== data.source2.id ||
          v.source2.type !== data.source2.type),
    }),
  },
  initialState,
)

export default {
  editLinks,
}
