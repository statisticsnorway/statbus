import React from 'react'
import { Provider } from 'react-redux'
import { Router, browserHistory, IndexRoute, IndexLink, Link, Route } from 'react-router'
import { syncHistoryWithStore } from 'react-router-redux'

import Home from './views/Home'
import About from './views/About'
import NotFound from './views/NotFound'

// Layout component
const Layout = props => (
  <div>
    <IndexLink to="/">Home</IndexLink>
    {' | '}
    <Link to="/about">About</Link>
    <br />
    {props.children}
  </div>
)

// Router component
const Routes = (
  <Route path="/" component={Layout}>
    <IndexRoute component={Home} />
    <Route path="about" component={About} />
    <Route path="*" component={NotFound} />
  </Route>
)

// App component
export default ({ store }) => (
  <Provider store={store}>
    <Router history={syncHistoryWithStore(browserHistory, store)} routes={Routes} />
  </Provider>
)
