import React from 'react'
import PropTypes from 'prop-types'
import { Button, Icon } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'

import ErrorMessage from './Error'
import SuccessMessage from './Success'
import LoadingMessage from './Loading'
import styles from './styles.pcss'

const renderChild = ({ id, message, code, dismiss, localize }) => {
  const localizedMessage = localize(message)
  switch (code) {
    case -1:
      return <ErrorMessage message={localizedMessage} dismiss={() => dismiss(id)} key={id} />
    case 1:
      return <LoadingMessage message={localizedMessage} dismiss={() => dismiss(id)} key={id} />
    case 2:
      return <SuccessMessage message={localizedMessage} dismiss={() => dismiss(id)} key={id} />
    default:
      return null
  }
}

const StatusBar = ({ status, dismiss, dismissAll, localize }) => (
  <div className={styles.root}>
    {status !== undefined && status.map
      && status.map(x => renderChild({ ...x, dismiss, localize }))}
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

StatusBar.propTypes = {
  localize: PropTypes.func.isRequired,
}

export default wrapper(StatusBar)
