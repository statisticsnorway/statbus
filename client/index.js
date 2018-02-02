import React from 'react'
import ReactDOM from 'react-dom'
import { AppContainer } from 'react-hot-loader'

import { getLocale } from 'helpers/locale'
import App from './App'
import configureStore from './store/configureStore'

const store = configureStore({ locale: getLocale() })
const rootNode = document.getElementById('root')

const render = (Component) => {
  ReactDOM.render(
    // eslint-disable-next-line react/jsx-filename-extension
    <AppContainer warnings={false}>
      <Component store={store} />
    </AppContainer>,
    rootNode,
  )
}

render(App)

if (module.hot) {
  module.hot.accept('./App', () => {
    render(App)
  })
  module.hot.accept('./store/combinedReducers', () => {
    // eslint-disable-next-line global-require
    const reducers = require('./store/combinedReducers').default
    return store.replaceReducer(reducers)
  })
}
