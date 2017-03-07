import { createReducer } from 'redux-act'

import * as actions from './actions'

const initialState = {
  statUnits: [],
}

const deletedStatUnits = createReducer(
  {

    [actions.fetchStatUnitSucceeded]:
      (state, { data }) =>
        ({
          statUnits: data,
        }),

    [actions.restoreSucceeded]:
      (state, { data }) =>
        ({
          statUnits: state.statUnits.filter(x => x.regId !== data),
        }),

  },
  initialState,
)

export default {
  deletedStatUnits,
}
