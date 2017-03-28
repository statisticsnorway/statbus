import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actionCreators from './actions'
import SearchStatUnit from './SearchStatUnit'

const { setQuery, ...actions } = actionCreators

export default connect(
  ({ statUnits }, { location: { query } }) =>
    ({
      ...statUnits,
      query,
    }),
  (dispatch, { location: { pathname } }) =>
    ({
      actions: {
        ...bindActionCreators(actions, dispatch),
        setQuery: (...params) => dispatch(setQuery(pathname)(...params)),
      },
    }),
)(SearchStatUnit)
