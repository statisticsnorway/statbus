import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import actionCreators from './actions'
import SearchStatUnit from './SearchStatUnit'

const { setQuery, ...actions } = actionCreators

export default connect(
  ({ statUnits, locale }, { location: { query } }) =>
    ({
      ...statUnits,
      query,
      localize: getText(locale),
    }),
  (dispatch, { location: { pathname } }) =>
    ({
      actions: {
        ...bindActionCreators(actions, dispatch),
        setQuery: (...params) => dispatch(setQuery(pathname)(...params)),
      },
    }),
)(SearchStatUnit)
