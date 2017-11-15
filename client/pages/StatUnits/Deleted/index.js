import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import actionCreators from './actions'
import DeletedList from './DeletedList'

const { setQuery, ...actions } = actionCreators

export default connect(
  ({ deletedStatUnits, locale }, { location: { query } }) => ({
    ...deletedStatUnits,
    localize: getText(locale),
    query,
  }),
  (dispatch, { location: { pathname } }) => ({
    actions: {
      ...bindActionCreators(actions, dispatch),
      setQuery: (...params) => dispatch(setQuery(pathname)(...params)),
    },
  }),
)(DeletedList)
