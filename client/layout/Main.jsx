import React from 'react'
import { Container } from 'semantic-ui-react'

import Breadcrumbs from './Breadcrumbs'
import StatusBar from './StatusBar'
import styles from './styles'

export default ({ children, routes }) => (
  <main className={styles.main}>
    <Breadcrumbs routes={routes} />
    <StatusBar />
    <Container>
      {children}
    </Container>
  </main>
)
