import { createReducer } from 'redux-act'

import * as actions from './actions'

const initialState = {
  statUnit: { },
}

export const editStatUnit = createReducer(
  {
    [actions.fetchStatUnitSucceeded]: (state, data) => ({
      ...state,
      statUnit: data,
    }),
    [actions.editForm]: (state, data) => ({
      ...state,
      statUnit: { ...state.statUnit, [data.propName]: data.value },
    }),
  },
  initialState,
)
