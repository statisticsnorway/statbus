import { createReducer } from 'redux-act'
import * as actionTypes from './actions'

const initialState = {
  statUnit: {},
  history: undefined,
}

const viewStatUnit = createReducer({
  [actionTypes.fetchStatUnitSucceeded]: (state, data) => ({
    ...state,
    statUnit: data,
  }),
  [actionTypes.fetchHistorySucceeded]: (state, data) => ({
    ...state,
    history: data,
  }),
}, initialState)

export default {
  viewStatUnit,
}
