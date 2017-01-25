import React from 'react'
import { Icon, Message } from 'semantic-ui-react'

import styles from './styles'

export default ({ message }) => (
  <Message
    className={styles.loading}
    content={message}
    icon={<Icon loading name="spinner" />}
    size="mini"
  />
)
