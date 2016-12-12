import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions'
import Search from './Search'

export default connect(
  ({ statUnits }) => ({ ...statUnits }),
  dispatch => bindActionCreators(actions, dispatch),
)(Search)
