import React from 'react'
import { Container } from 'semantic-ui-react'

import StatusBar from '../StatusBar'
import styles from './styles'

export default ({ children }) => (
  <main className={styles.root}>
    <StatusBar />
    <Container>
      {children}
    </Container>
  </main>
)
