import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions'
import Edit from './Edit'

export default connect(
  ({ editUser }, { params }) => ({ ...editUser, ...params }),
  dispatch => bindActionCreators(actions, dispatch),
)(Edit)
