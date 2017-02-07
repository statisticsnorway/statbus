import { createReducer } from 'redux-act'

import * as actions from './actions'

const initialState = {
  statUnit: {
    properties: [],
  },
  errors: {},
}

const editStatUnit = createReducer(
  {
    [actions.fetchStatUnitSucceeded]: (state, data) => ({
      ...state,
      statUnit: data,
    }),
    [actions.setErrors]: (state, data) => ({
      ...state,
      errors: data,
    }),
    [actions.clear]: state => ({
      ...state,
      statUnit: initialState.statUnit,
    }),
  },
  initialState,
)

export default {
  editStatUnit,
}
