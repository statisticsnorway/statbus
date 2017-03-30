import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions'
import List from './List'

export default connect(
  ({ regions }) => ({ ...regions }),
  dispatch => bindActionCreators(actions, dispatch),
)(List)
