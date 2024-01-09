import { createReducer } from 'redux-act'

import { actionTypes as types } from './actions.js'

const defaultState = {
  properties: undefined,
  permissions: undefined,
  errors: undefined,
}

const handlers = {
  [types.setMeta]: (state, { properties, permissions }) => ({
    ...state,
    properties,
    permissions,
  }),
  [types.fetchError]: (state, errors) => ({ ...state, errors }),
  [types.clear]: () => defaultState,
}

export default createReducer(handlers, defaultState)
