import React from 'react'
import { Container } from 'semantic-ui-react'

import Header from './Header'
import Breadcrumbs from './Breadcrumbs'
import StatusBar from './StatusBar'
import Notification from './Notification'
import Footer from './Footer'
import styles from './styles'

const Layout = ({ children, routes }) => (
  <div className={styles.layout}>
    <Header />
    <main className={styles.main}>
      <Breadcrumbs routes={routes} />
      <StatusBar />
      <Notification />
      <Container>
        {children}
      </Container>
    </main>
    <Footer />
  </div>
)

const { arrayOf, node, shape, string } = React.PropTypes
Layout.propTypes = {
  children: node.isRequired,
  routes: arrayOf(shape({
    path: string,
  })).isRequired,
}

export default Layout
