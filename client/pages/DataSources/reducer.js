import { createReducer } from 'redux-act'

import * as actions from './actions'

const defaultState = {
  dataSources: {
    items: [],
  },
}

const handlers = {
  [actions.fetchDataSourcesSucceeded]:
    (state, data) => ({
      dataSources: {
        items: data,
      },
    }),
}

export default createReducer(handlers, defaultState)
