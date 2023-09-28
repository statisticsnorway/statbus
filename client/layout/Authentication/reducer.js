import { createReducer } from 'redux-act'

import { authentication as actions } from '/client/helpers/actionCreators'

const defaultState = { open: false }

const handlers = {
  [actions.showAuthentication]: () => ({
    open: true,
  }),
  [actions.hideAuthentication]: () => ({
    open: false,
  }),
}

export default createReducer(handlers, defaultState)
