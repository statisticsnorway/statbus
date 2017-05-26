import { createReducer } from 'redux-act'

import * as actions from './actions'

const initialState = {
  inconsistentRecords: [],
  totalCount: 0,
  loading: true,
}

const inconsistentRecords = createReducer(
  {
    [actions.logicalChecksSucceded]: (state, data) => ({
      ...state,
      inconsistentRecords: data.result,
      totalCount: data.totalCount,
      loading: false,
      error: undefined,
    }),
    [actions.logicalChecksFalled]: (state, data) => ({
      ...state,
      inconsistentRecords: [],
      totalCount: 0,
      loading: false,
      error: data,
    }),
  },
  initialState,
)

export default {
  inconsistentRecords,
}
