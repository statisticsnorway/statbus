import { createReducer } from 'redux-act'

import * as actions from './actions'

const initialState = {
  formData: {},
  statUnits: [],
  totalCount: 0,
}

const statUnits = createReducer(
  {
    [actions.updateFilter]:
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

    [actions.deleteStatUnitSucceeded]:
      (state, data) =>
        ({
          ...state,
          statUnits: state.statUnits.filter(r => r.id !== data),
          totalCount: state.totalCount - 1,
        }),
  },
  initialState,
)

export default {
  statUnits,
}
