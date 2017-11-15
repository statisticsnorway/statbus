import React from 'react'
import { node } from 'prop-types'
import { Container } from 'semantic-ui-react'

import Header from './Header'
import Breadcrumbs, { routerPropTypes } from './Breadcrumbs'
import StatusBar from './StatusBar'
import Notification from './Notification'
import Footer from './Footer'
import styles from './styles.pcss'

const Layout = ({ children, routerProps }) => (
  <div className={styles.layout}>
    <Header />
    <main className={styles.main}>
      <Breadcrumbs routerProps={routerProps} />
      <StatusBar />
      <Notification />
      <Container>{children}</Container>
    </main>
    <Footer />
  </div>
)

Layout.propTypes = {
  children: node.isRequired,
  routerProps: routerPropTypes.isRequired,
}

export default Layout
