import { createReducer } from 'redux-act'

import { selectLocale } from '/helpers/actionCreators'
import config from '/helpers/config'

const handlers = {
  [selectLocale]: (state, data) => data,
}

export default createReducer(handlers, config.defaultLocale)
