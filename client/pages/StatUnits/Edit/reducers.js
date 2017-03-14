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
    [actions.editForm]: (state, { name, value }) => ({
      ...state,
      statUnit: {
        ...state.statUnit,
        properties: state.statUnit.properties.map(p => p.name === name ? { ...p, value } : p),
      },
    }),
  },
  initialState,
)

export default {
  editStatUnit,
}
