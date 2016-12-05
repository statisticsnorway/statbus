import { createReducer } from 'redux-act'

import * as actions from './actions'

export const statUnits = createReducer(
  {
    [actions.fetchStatUnitsSucceeded]: (state, data) => ({
      ...state,
      statUnits: data.result,
      totalCount: data.totalCount,
      totalPages: data.totalPages,
    }),
    [actions.deleteStatUnitSucceeded]: (state, data) => ({
      ...state,
      statUnits: state.statUnits.filter(r => r.id !== data),
      totalCount: state.totalCount - 1,
    }),
  },
  {
    statUnits: [],
    totalCount: 0,
    totalPages: 0,
  },
)
