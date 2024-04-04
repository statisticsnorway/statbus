import React, { useState } from 'react'
import { node, shape } from 'prop-types'
import { Container, Segment } from 'semantic-ui-react'

import Header from '../Header.jsx'
import Breadcrumbs, { routerPropTypes } from '../Breadcrumbs.jsx'
import Notification from '../Notification/index.js'
import Footer from '../Footer.jsx'
import styles from '../styles.scss'
import Authentication from '../Authentication/index.js'

const Layout = ({ children, routerProps, stateLocation }) => {
  const [isLoading, setIsLoading] = useState(false)
  return (
    <div className={styles.layout}>
      <Segment loading={isLoading}>
        <Header changeLoading={value => setIsLoading(value)} />
        <main className={styles.main}>
          <Notification />
          <Authentication />
          <Container>
            <Breadcrumbs routerProps={routerProps} previousRoute={stateLocation.previousLocation} />
            <Container>{children}</Container>
          </Container>
        </main>
        <Footer />
      </Segment>
    </div>
  )
}

Layout.propTypes = {
  children: node.isRequired,
  routerProps: routerPropTypes.isRequired,
  stateLocation: shape({}),
}

Layout.defaultProps = {
  stateLocation: undefined,
}

export default Layout
