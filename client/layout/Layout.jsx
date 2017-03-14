import React from 'react'

import Header from 'components/Header'
import Main from 'components/Main'
import Footer from 'components/Footer'
import styles from './styles'

export default ({ routes, children }) => (
  <div className={styles.root}>
    <Header />
    <Main routes={routes}>
      {children}
    </Main>
    <Footer />
  </div>
)
