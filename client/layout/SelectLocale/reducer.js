import { createReducer } from 'redux-act'

import { selectLocale } from '/client/helpers/actionCreators'
import config from '/client/helpers/config'

const handlers = {
  [selectLocale]: (state, data) => data,
}

export default createReducer(handlers, config.defaultLocale)
