import React from 'react'
import { render } from 'react-dom'
import { AppContainer } from 'react-hot-loader'

import App from './App'
import configureStore from './store/configureStore'

const store = configureStore()
const rootNode = document.getElementById('root')
render(
  // eslint-disable-next-line react/jsx-filename-extension
  <AppContainer>
    <App store={store} />
  </AppContainer>,
  rootNode,
)

// Hot Module Replacement
if (module.hot) {
  module.hot.accept('./App', () => {
    render(
      <AppContainer>
        <App store={store} />
      </AppContainer>,
      rootNode,
    )
  })
}
