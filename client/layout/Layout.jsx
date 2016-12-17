import React from 'react'

import Header from 'components/Header'
import Main from 'components/Main'
import Footer from 'components/Footer'
import styles from './styles'

export default props => (
  <div className={styles.root}>
    <Header />
    <Main>
      {props.children}
    </Main>
    <Footer />
  </div>
)
