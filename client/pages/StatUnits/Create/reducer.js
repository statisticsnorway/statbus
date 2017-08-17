import { createReducer } from 'redux-act'

import { actionTypes as types } from './actions'

const defaultState = {
  properties: undefined,
  dataAccess: undefined,
  errors: undefined,
}

const handlers = {
  [types.setMeta]: (state, { properties, dataAccess }) => ({
    properties,
    dataAccess,
    errors: undefined,
  }),
  [types.setErrors]: (state, errors) => ({
    properties: undefined,
    dataAccess: undefined,
    errors,
  }),
  [types.clear]: () => defaultState,
}

export default createReducer(handlers, defaultState)
