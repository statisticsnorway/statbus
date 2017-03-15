import React from 'react'

import Header from './Header'
import Main from './Main'
import Footer from './Footer'
import styles from './styles'

export default ({ routes, children }) => (
  <div className={styles.layout}>
    <Header />
    <Main routes={routes}>
      {children}
    </Main>
    <Footer />
  </div>
)
