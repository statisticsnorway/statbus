import { createReducer } from 'redux-act'

import { actionTypes as types } from './actions'

const defaultState = {
  properties: undefined,
  dataAccess: undefined,
  isSubmitting: false,
}

const handlers = {
  [types.setMeta]: (state, { properties, dataAccess }) => ({
    properties,
    dataAccess,
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
