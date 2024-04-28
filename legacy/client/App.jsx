import React from 'react'
import { Provider } from 'react-redux'
import { Router, browserHistory } from 'react-router'
import { syncHistoryWithStore } from 'react-router-redux'

import './styles.scss'
import routes from './routes.jsx'

// eslint-disable-next-line react/prop-types
export default ({ store }) => (
  <Provider store={store}>
    <Router
      key={Math.random()}
      history={syncHistoryWithStore(browserHistory, store)}
      routes={routes}
    />
  </Provider>
)
