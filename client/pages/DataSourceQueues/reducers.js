import { createReducer } from 'redux-act'

import * as actions from './actions'

const initialState = {
  formData: {},
  result: [],
  totalCount: 0,
  fetching: false,
  error: undefined,
}

const datasourcequeues = createReducer(
  {
    [actions.fetchDataSuccessed]: (state, data) => ({
      ...state,
      result: data.result,
      totalCount: data.totalCount,
      fetching: false,
      error: undefined,
    }),
    [actions.fetchDataFailed]: (state, data) => ({
      ...state,
      data: undefined,
      fetching: false,
      error: data,
    }),
    [actions.fetchDataStarted]: state => ({
      ...state,
      fetching: true,
      error: undefined,
    }),
    [actions.updateFilter]:
      (state, data) =>
        ({
          ...state,
          formData: { ...state.formData, ...data },
        }),
  },
  initialState,
)

export default {
  datasourcequeues,
}
