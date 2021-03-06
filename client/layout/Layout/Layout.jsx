import React from 'react'
import { node, shape } from 'prop-types'
import { Container } from 'semantic-ui-react'

import Header from '../Header'
import Breadcrumbs, { routerPropTypes } from '../Breadcrumbs'
import Notification from '../Notification'
import Footer from '../Footer'
import styles from '../styles.pcss'
import Authentication from '../Authentication'

const Layout = ({ children, routerProps, stateLocation }) => (
  <div className={styles.layout}>
    <Header />
    <main className={styles.main}>
      <Notification />
      <Authentication />
      <Container>
        <Breadcrumbs routerProps={routerProps} previousRoute={stateLocation.previousLocation} />
        <Container>{children}</Container>
      </Container>
    </main>
    <Footer />
  </div>
)

Layout.propTypes = {
  children: node.isRequired,
  routerProps: routerPropTypes.isRequired,
  stateLocation: shape({}),
}

Layout.defaultProps = {
  stateLocation: undefined,
}

export default Layout
