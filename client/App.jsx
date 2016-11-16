import React from 'react'
import { Provider } from 'react-redux'
import { Router, browserHistory, IndexRoute, Route } from 'react-router'
import { syncHistoryWithStore } from 'react-router-redux'

import Layout from './Layout'
import Home from './pages/Home'
import RolesRoutes from './pages/Roles'
import UsersRoutes from './pages/Users'
import About from './pages/About'
import NotFound from './pages/NotFound'

// Router component
const Routes = (
  <Route path="/" component={Layout}>
    <IndexRoute component={Home} />
    {RolesRoutes}
    {UsersRoutes}
    <Route path="about" component={About} />
    <Route path="*" component={NotFound} />
  </Route>
)

// App component
export default ({ store }) => (
  <Provider store={store}>
    <Router
      key={Math.random()}
      history={syncHistoryWithStore(browserHistory, store)}
      routes={Routes}
    />
  </Provider>
)
