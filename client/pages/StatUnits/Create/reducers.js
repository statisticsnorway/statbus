import { createReducer } from 'redux-act'
import * as actions from './actions'

const initialState = {
  statUnit: {
    type: 1,
  },
}

const createStatUnit = createReducer({
  [actions.clearForm]: state => ({
    ...state,
    statUnit: {
      type: 1,
    },
  }),
  [actions.editForm]: (state, data) => ({
    ...state,
    statUnit: {
      ...state.statUnit,
      [data.propName]: data.value,
    },
  }),
}, initialState)

export default { createStatUnit }
