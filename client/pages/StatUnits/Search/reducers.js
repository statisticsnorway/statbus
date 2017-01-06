import { createReducer } from 'redux-act'

import * as actions from './actions'

const initialState = {
  statUnits: [],
  totalCount: 0,
  totalPages: 0,
  queryObj: {},
}

export const statUnits = createReducer(
  {
    [actions.fetchStatUnitsSucceeded]: (state, { result, totalCount, totalPages, queryObj }) => ({
      ...state,
      statUnits: result,
      totalCount,
      totalPages,
      queryObj,
    }),
    [actions.deleteStatUnitSucceeded]: (state, data) => ({
      ...state,
      statUnits: state.statUnits.filter(r => r.id !== data),
      totalCount: state.totalCount - 1,
    }),
  },
  initialState,
)
