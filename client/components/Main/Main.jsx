import React from 'react'
import { Container } from 'semantic-ui-react'

import BreadCrumbs from 'components/BreadCrumbs'
import StatusBar from 'components/StatusBar'
import styles from './styles'

export default ({ children, routes }) => (
  <main className={styles.root}>
    <BreadCrumbs routes={routes} />
    <StatusBar />
    <Container>
      {children}
    </Container>
  </main>
)
