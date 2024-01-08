import { createReducer } from 'redux-act'

import { actionTypes as types } from './actions.js'

const defaultState = {
  properties: undefined,
  permissions: undefined,
  isSubmitting: false,
}

const handlers = {
  [types.setMeta]: (state, { properties, permissions }) => ({
    properties,
    permissions,
    isSubmitting: false,
  }),
  [types.startSubmitting]: state => ({
    ...state,
    isSubmitting: true,
  }),
  [types.stopSubmitting]: state => ({
    ...state,
    isSubmitting: false,
  }),
  [types.clear]: () => defaultState,
}

export default createReducer(handlers, defaultState)
