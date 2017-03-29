import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions'
import Edit from './Edit'

export default connect(
  ({ editAddress }, { params }) => ({ ...editAddress, ...params }),
  dispatch => bindActionCreators(actions, dispatch),
)(Edit)
