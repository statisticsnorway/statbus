import React from 'react'

import ErrorMessage from './Error'
import SuccessMessage from './Success'
import LoadingMessage from './Loading'
import styles from './styles'

const renderChild = (status) => {
  switch (status) {
    case -1:
      return <ErrorMessage />
    case 1:
      return <LoadingMessage />
    case 2:
      return <SuccessMessage />
    default:
      return null
  }
}

export default ({ status }) => (
  <div className={styles.root}>
    {renderChild(status)}
  </div>
)
