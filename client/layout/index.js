import { connect } from 'react-redux'

import Layout from './Layout'

export default connect(
  (_, { routes }) => ({ routes }),
)(Layout)
