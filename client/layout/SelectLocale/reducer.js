import { createReducer } from 'redux-act'

import { selectLocale } from 'helpers/actionCreators'

// TODO: default locale should be configurable
const defaultState = 'en-GB'

const handlers = {
  [selectLocale]: (state, data) => data,
}

export default createReducer(handlers, defaultState)
