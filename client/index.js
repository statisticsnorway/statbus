import React from 'react'
import { render } from 'react-dom'
import { Provider } from 'react-redux'
import { Router, browserHistory } from 'react-router'
import { syncHistoryWithStore } from 'react-router-redux'

import Routes from './Routes'
import configureStore from './configureStore'

const store = configureStore()
const history = syncHistoryWithStore(browserHistory, store)

render(
  // eslint-disable-next-line react/jsx-filename-extension
  <Provider store={store}>
    <Router history={history} routes={Routes} />
  </Provider>,
  document.getElementById('root')
)
