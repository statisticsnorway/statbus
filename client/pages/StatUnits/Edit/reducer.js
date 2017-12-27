import { createReducer } from 'redux-act'

import { actionTypes as types } from './actions'

const defaultState = {
  properties: undefined,
  permissions: undefined,
}

const handlers = {
  [types.setMeta]: (state, { properties, permissions }) => ({
    properties,
    permissions,
  }),
  [types.clear]: () => defaultState,
}

export default createReducer(handlers, defaultState)
