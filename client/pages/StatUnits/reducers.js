import { createReducer } from 'redux-act'

import * as actions from './actions'

const initialState = {
  enterpriseGroupsLookup: [],
  enterpriseUnitsLookup: [],
  legalUnitsLookup: [],
  localUnitsLookup: [],
}

const statUnitsCommon = createReducer(
  {
    [actions.fetchEnterpriseGroupsLookupSucceeded]: (state, data) => ({
      ...state,
      enterpriseGroupsLookup: data,
    }),
    [actions.fetchEnterpriseUnitsLookupSucceeded]: (state, data) => ({
      ...state,
      enterpriseUnitsLookup: data,
    }),
    [actions.fetchLegalUnitsLookupSucceeded]: (state, data) => ({
      ...state,
      legalUnitsLookup: data,
    }),
    [actions.fetchLocallUnitsLookupSucceeded]: (state, data) => ({
      ...state,
      localUnitsLookup: data,
    }),
  },
  initialState,
)

export default {
  statUnitsCommon,
}
