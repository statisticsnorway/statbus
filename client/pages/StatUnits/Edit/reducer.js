import { createReducer } from 'redux-act'

import { actionTypes as types } from './actions'

const defaultState = {
  properties: undefined,
  dataAccess: undefined,
}

const handlers = {
  [types.setMeta]: (state, { properties, dataAccess }) => ({
    properties,
    dataAccess,
  }),
  [types.clear]: () => defaultState,
}

export default createReducer(handlers, defaultState)
