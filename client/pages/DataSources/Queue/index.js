import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import actions, { setQuery } from './actions'
import DataSourcesQueue from './Queue'

export default connect(
  ({ datasourcequeues, locale }, { location: { query } }) => ({
    ...datasourcequeues,
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
)(DataSourcesQueue)
