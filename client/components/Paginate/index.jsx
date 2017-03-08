import { connect } from 'react-redux'

import Paginate from './Paginate'

export default connect(
  (_, { totalPages, onChange, location: { query, search } }) => ({
    query,
    queryString: search,
    totalPages,
    onChange,
  }),
)(Paginate)
