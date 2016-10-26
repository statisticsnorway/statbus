import { createReducer } from 'redux-act'
import * as actions from './actions'

export const counter = createReducer({
  [actions.add]: (state, data) => state + data,
  [actions.decrement]: state => state - 1,
  [actions.increment]: state => state - 1,
}, 0)
