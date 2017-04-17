import { createReducer } from 'redux-act'
import * as actionTypes from './actions'

const initialState = {
  statUnit: {},
  history: {},
  historyDetails: {},
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
  [actionTypes.fetchHistoryDetailsStarted]: state => ({
    ...state,
    historyDetails: initialState.historyDetails,
  }),
  [actionTypes.fetchHistoryDetailsSucceeded]: (state, data) => ({
    ...state,
    historyDetails: data,
  }),
}, initialState)

export default {
  viewStatUnit,
}
