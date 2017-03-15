import React from 'react'
import { Button, Icon } from 'semantic-ui-react'

import ErrorMessage from './Error'
import SuccessMessage from './Success'
import LoadingMessage from './Loading'
import styles from './styles'

const renderChild = ({ id, message, code, dismiss }) => {
  switch (code) {
    case -1:
      return <ErrorMessage message={message} dismiss={() => dismiss(id)} key={id} />
    case 1:
      return <LoadingMessage message={message} dismiss={() => dismiss(id)} key={id} />
    case 2:
      return <SuccessMessage message={message} dismiss={() => dismiss(id)} key={id} />
    default:
      return null
  }
}

export default ({ status, dismiss, dismissAll }) => (
  <div className={styles.root}>
    {status !== undefined && status.map
      && status.map(x => renderChild({ ...x, dismiss }))}
    {status.length > 1 && status.map
      && <Button
        onClick={dismissAll}
        className={styles.close}
        color="grey"
        basic
        icon
      >
        <Icon name="remove" />
      </Button>}
  </div>
)
