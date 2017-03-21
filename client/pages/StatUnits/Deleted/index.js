import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actionCreators from './actions'
import DeletedList from './DeletedList'

const { setQuery, ...actions } = actionCreators

export default connect(
  (state, { location: { query } }) => ({
    ...state.deletedStatUnits,
    query,
  }),
  (dispatch, { location: { pathname } }) => ({
    actions: {
      ...bindActionCreators(actions, dispatch),
      setQuery: (...params) => dispatch(setQuery(pathname)(...params)),
    },
  }),
)(DeletedList)
