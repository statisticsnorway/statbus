import React from 'react'
import { Message } from 'semantic-ui-react'

import styles from './styles'

export default ({ message }) => (
  <Message
    className={styles.loading}
    content={message}
    icon="loading spinner"
    size="mini"
  />
)
