import { createReducer } from 'redux-act'

import * as actions from './actions'
import { updateFilter } from '../actions'

const initialState = {
  formData: {},
  statUnits: [],
  totalCount: 0,
}

const deletedStatUnits = createReducer(
  {
    [updateFilter]:
      (state, data) =>
        ({
          ...state,
          formData: { ...state.formData, ...data },
        }),

    [actions.fetchDataSucceeded]:
      (state, { result, totalCount }) =>
        ({
          ...state,
          statUnits: result,
          totalCount,
        }),
  },
  initialState,
)

export default {
  deletedStatUnits,
}
