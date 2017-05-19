import { createReducer } from 'redux-act'
import { actionTypes as types } from './actions'

const initialState = {
  type: 1,
  statUnit: {
    id: null,
    properties: [],
    statUnitType: 1,
    dataAccess: [],
  },
  schema: undefined,
  errors: {},
}

const createStatUnit = createReducer({
  [types.fetchModelSuccess]: (state, { statUnit, schema }) => ({
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
  [types.changeType]: (state, type) => ({
    ...state,
    type,
    statUnit: initialState.statUnit,
  }),
}, initialState)

export default { createStatUnit }
