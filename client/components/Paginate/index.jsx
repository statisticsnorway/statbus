import { connect } from 'react-redux'

import Paginate from './Paginate'

export default connect(
  ({ routing: { locationBeforeTransitions: { pathname, query, search } } }, ownProps) => ({
    routing: {
      ...query,
      pathname,
      queryString: search,
    },
    ...ownProps,
  }),
)(Paginate)
