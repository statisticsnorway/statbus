import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions'
import Search from './Search'

export default connect(
  ({ statUnits }, { params, location: { query, pathname } }) =>
  ({ ...statUnits, params, query, pathname }),
  dispatch => bindActionCreators(actions, dispatch),
)(Search)
