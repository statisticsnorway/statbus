import { createReducer } from 'redux-act'

import * as actions from './actions'

const initialState = {
  addresses: [],
  totalPages: 0,
  currentPage: 0,
  fetching: false,
  error: undefined,
}

const addressList = createReducer(
  {
    [actions.fetchAddressesSuccessed]: (state, { addresses, totalPages, currentPage }) => ({
      ...state,
      addresses,
      totalPages,
      currentPage,
      fetching: false,
      error: undefined,
    }),
    [actions.fetchAddressesFailed]: (state, data) => ({
      ...state,
      addressList: [],
      fetching: false,
      error: data,
    }),
    [actions.fetchAddressesStarted]: state => ({
      ...state,
      fetching: true,
      error: undefined,
    }),
  },
  initialState,
)

export default {
  addressList,
}
