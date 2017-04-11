import { createReducer } from 'redux-act'
import * as actionTypes from './actions'

const initialState = {
  statUnit: {},
  history: {},
}

const viewStatUnit = createReducer({
  [actionTypes.fetchStatUnitSucceeded]: (state, data) => ({
    ...state,
    statUnit: data,
  }),
  [actionTypes.fetchHistoryStarted]: state => ({
    ...state,
    history: initialState.history,
  }),
  [actionTypes.fetchHistorySucceeded]: (state, data) => ({
    ...state,
    history: data,
  }),
}, initialState)

export default {
  viewStatUnit,
}
