import { createReducer } from 'redux-act'
import * as actionTypes from './actions'

const initialState = {
  statUnit: {},
  activeTab: 'main',
}

const viewStatUnit = createReducer({
  [actionTypes.fetchStatUnitSucceeded]: (state, data) => ({
    ...state,
    statUnit: data,
  }),
}, initialState)

export default {
  viewStatUnit,
}
