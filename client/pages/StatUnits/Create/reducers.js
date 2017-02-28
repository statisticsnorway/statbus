import { createReducer } from 'redux-act'
import * as actions from './actions'

const initialState = {
  type: 1,
  statUnitModel: {
    properties: [],
  },
  errors: {},
}

const createStatUnit = createReducer({
  [actions.getModelSuccess]: (state, data) => ({
    ...state,
    statUnitModel: data,
    errors: {},
  }),
  [actions.changeType]: (state, data) => ({
    ...state,
    type: data,
    statUnitModel: initialState.statUnitModel,
  }),
  [actions.editForm]: (state, { name, value }) => ({
    ...state,
    statUnitModel: {
      ...state.statUnitModel,
      properties: state.statUnitModel.properties.map(p => p.name === name ? { ...p, value } : p),
    },
  }),
}, initialState)

export default { createStatUnit }
