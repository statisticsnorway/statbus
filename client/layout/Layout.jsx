import React from 'react'

import Header from 'components/Header'
import Main from 'components/Main'
import Footer from 'components/Footer'
import styles from './styles'

export default ({ children }) => (
  <div className={styles.root}>
    <Header />
    <Main>{children}</Main>
    <Footer />
  </div>
)
