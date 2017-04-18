import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions, { setQuery } from './actions'
import ViewDataSourceQueues from './ViewDataSourceQueues'

export default connect(
  ({ datasourcequeues }, { location: { query } }) => ({
    ...datasourcequeues,
    query,
  }),
  (dispatch, { location: { pathname } }) =>
   ({
     actions: {
       ...bindActionCreators(actions, dispatch),
       setQuery: (...params) => dispatch(setQuery(pathname)(...params)),
     },
   }),
)(ViewDataSourceQueues)

