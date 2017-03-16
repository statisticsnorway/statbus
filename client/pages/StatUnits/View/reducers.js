import { createReducer } from 'redux-act'
import * as actionTypes from './actions'
import tabEnum from './tabs/tabs'

const initialState = {
  statUnit: {},
  activeTab: tabEnum.main,
}

const viewStatUnit = createReducer({
  [actionTypes.fetchStatUnitSucceeded]: (state, data) => ({
    ...state,
    statUnit: data,
  }),
  [actionTypes.handleTabClickSucceeded]: (state, name) => ({
    ...state,
    activeTab: name,
  }),
}, initialState)

export default {
  viewStatUnit,
}
