import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from '/helpers/locale'
import actions from './actions.js'
import List from './List.jsx'

export default connect(
  ({ roles, locale }, { location: { query } }) => ({
    ...roles,
    query,
    localize: getText(locale),
  }),
  dispatch => bindActionCreators(actions, dispatch),
)(List)
