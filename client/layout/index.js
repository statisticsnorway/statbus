import { connect } from 'react-redux'

import Layout from './Layout'

export default connect((_, { routes, location, params }) => ({
  routerProps: {
    routes,
    location,
    params,
  },
}))(Layout)
