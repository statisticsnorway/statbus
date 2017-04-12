import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions'
import DeleteLink from './DeleteLink'

export default connect(
  ({ deleteLinks }) => ({ ...deleteLinks }),
  dispatch => bindActionCreators(actions, dispatch),
)(DeleteLink)
