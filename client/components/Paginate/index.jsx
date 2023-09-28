import { connect } from 'react-redux'

import { getText } from '/client/helpers/locale'
import Paginate from './Paginate'

export default connect((
  {
    locale,
    routing: {
      locationBeforeTransitions: { pathname, query, search },
    },
  },
  ownProps,
) => ({
  routing: {
    ...query,
    pathname,
    queryString: search,
  },
  localize: getText(locale),
  ...ownProps,
}))(Paginate)
