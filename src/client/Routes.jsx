import React from 'react'
import { Route, IndexRoute } from 'react-router'

import App from './App'
import Home from './views/Home'
import About from './views/About'
import NotFound from './views/NotFound'

export default (
  <Route path="/" component={App}>
    <IndexRoute component={Home} />
    <Route path="about" component={About} />
    <Route path="*" component={NotFound} />
  </Route>
)
