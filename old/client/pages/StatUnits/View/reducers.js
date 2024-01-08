import { createReducer } from 'redux-act'
import * as actionTypes from './actions.js'

const initialState = {
  statUnit: undefined,
  history: {},
  historyDetails: {},
  errorMessage: undefined,
}

const viewStatUnit = createReducer(
  {
    [actionTypes.fetchStatUnitSucceeded]: (state, data) => ({
      ...state,
      statUnit: data,
      errorMessage: undefined,
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
        instSectorCode: data,
      },
    }),
    [actionTypes.fetchLegalFormSucceeded]: (state, data) => ({
      ...state,
      statUnit: {
        ...state.statUnit,
        legalForm: data,
      },
    }),
    [actionTypes.fetchUnitStatusSucceeded]: (state, data) => ({
      ...state,
      statUnit: {
        ...state.statUnit,
        unitStatusId: data,
      },
    }),
    [actionTypes.fetchStatUnitFailed]: (state, data) => ({
      ...state,
      statUnit: Object,
      errorMessage: data,
    }),
    [actionTypes.clear]: () => initialState,
  },
  initialState,
)

export default {
  viewStatUnit,
}
