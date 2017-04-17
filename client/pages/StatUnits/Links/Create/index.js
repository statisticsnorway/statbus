import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions'
import CreateLink from './CreateLink'

export default connect(
  ({ editLinks }) => ({ ...editLinks }),
  dispatch => bindActionCreators(actions, dispatch),
)(CreateLink)
