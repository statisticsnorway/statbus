import { createReducer } from 'redux-act'

import { actionTypes as types } from './actions'

const initialState = {
  statUnit: {
    id: null,
    properties: [],
    statUnitType: undefined,
    dataAccess: [],
  },
  schema: undefined,
  errors: {},
}

const editStatUnit = createReducer({
  [types.fetchStatUnitSucceeded]: (state, { statUnit, schema }) => ({
    ...state,
    statUnit,
    schema,
  }),
  [types.setErrors]: (state, errors) => ({
    ...state,
    errors,
  }),
  [types.clear]: state => ({
    ...state,
    statUnit: initialState.statUnit,
  }),
  [types.editForm]: (state, formData) => ({
    ...state,
    statUnit: {
      ...state.statUnit,
      properties: state.statUnit.properties.map(p => ({ ...p, value: formData[p.name] })),
    },
  }),
}, initialState)

export default { editStatUnit }
