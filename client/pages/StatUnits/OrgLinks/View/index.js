import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions'
import ViewOrgLinks from './ViewOrgLinks'

export default connect(
  ({ viewOrgLinks }) => ({ ...viewOrgLinks }),
  dispatch => bindActionCreators(actions, dispatch),
)(ViewOrgLinks)
