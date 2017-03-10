import { createReducer } from 'redux-act'

import * as actions from './actions'

const initialState = {
  formData: {},
  statUnits: [],
}

const deletedStatUnits = createReducer(
  {
    [actions.updateForm]:
      (state, { data }) =>
        ({
          ...state,
          formData: { ...state.form, ...data },
        }),

    [actions.fetchStatUnitSucceeded]:
      (state, { data }) =>
        ({
          ...state,
          statUnits: data.result,
        }),

    [actions.restoreSucceeded]:
      (state, { data }) =>
        ({
          ...state,
          statUnits: state.statUnits.filter(x => x.regId !== data),
        }),

  },
  initialState,
)

export default {
  deletedStatUnits,
}
