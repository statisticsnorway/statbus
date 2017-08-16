import { createReducer } from 'redux-act'

import { actionTypes as types } from './actions'

const defaultState = {
  properties: undefined,
  dataAccess: undefined,
  schema: undefined,
  errors: undefined,
}

const handlers = {
  [types.setMeta]: (state, { properties, dataAccess, schema }) => ({
    properties,
    dataAccess,
    schema,
    errors: undefined,
  }),
  [types.setErrors]: (state, errors) => ({
    properties: undefined,
    dataAccess: undefined,
    schema: undefined,
    errors,
  }),
  [types.clear]: () => defaultState,
}

export default createReducer(handlers, defaultState)
