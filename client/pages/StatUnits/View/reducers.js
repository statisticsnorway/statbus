import { createReducer } from 'redux-act'
import * as actionTypes from './actions'

const initialState = {
  statUnit: undefined,
  history: {},
  historyDetails: {},
}

const viewStatUnit = createReducer(
  {
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
    [actionTypes.fetchSectorSucceeded]: (state, data) => ({
      ...state,
      statUnit: {
        ...state.statUnit,
        instSectorCodeId: data,
      },
    }),
    [actionTypes.fetchLegalFormSucceeded]: (state, data) => ({
      ...state,
      statUnit: {
        ...state.statUnit,
        legalFormId: data,
      },
    }),
  },
  initialState,
)

export default {
  viewStatUnit,
}
