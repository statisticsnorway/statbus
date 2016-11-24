import React from 'react'
import { Button, Icon } from 'semantic-ui-react'

import ErrorMessage from './Error'
import SuccessMessage from './Success'
import LoadingMessage from './Loading'
import styles from './styles'

const renderChild = (message, code) => {
  switch (code) {
    case -1:
      return <ErrorMessage message={message} key={message} />
    case 1:
      return <LoadingMessage message={message} key={message} />
    case 2:
      return <SuccessMessage message={message} key={message} />
    default:
      return null
  }
}

export default ({ messages, code, dismiss }) => (
  <div className={styles.root}>
    {messages !== undefined && messages.map
      && <Button onClick={() => { dismiss() }} icon><Icon name="remove" /></Button>}
    {messages !== undefined && messages.map
      && messages.map(message => renderChild(message, code))}
  </div>
)
