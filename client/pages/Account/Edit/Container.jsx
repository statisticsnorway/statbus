import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions'
import Edit from './EditDetails'

export default connect(
  ({ editAccount }, { params }) => ({ ...editAccount, ...params }),
  dispatch => bindActionCreators(actions, dispatch),
)(Edit)
