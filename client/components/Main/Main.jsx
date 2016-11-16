import React from 'react'
import { Container } from 'semantic-ui-react'

import StatusBar from '../StatusBar'
import styles from './styles'

export default ({ children, status = 0 }) => (
  <main className={styles.root}>
    <StatusBar status={status} />
    <Container>
      {children}
    </Container>
  </main>
)
