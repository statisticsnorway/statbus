import { createReducer } from 'redux-act'

import * as actions from './actions'

const initialState = {
  formData: {},
  statUnits: [],
  totalCount: 0,
  totalPages: 1,
}

const deletedStatUnits = createReducer(
  {
    [actions.updateForm]:
      (state, data) =>
        ({
          ...state,
          formData: { ...state.formData, ...data },
        }),

    [actions.fetchStatUnitSucceeded]:
      (state, data) =>
        ({
          ...state,
          statUnits: data.result,
          totalCount: data.totalCount,
          totalPages: data.totalPages,
        }),

    [actions.restoreSucceeded]:
      (state, data) =>
        ({
          ...state,
          statUnits: state.statUnits.filter(x => x.regId !== data),
          totalCount: state.totalCount - 1,
        }),
  },
  initialState,
)

export default {
  deletedStatUnits,
}
