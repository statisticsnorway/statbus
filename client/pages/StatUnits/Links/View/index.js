import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions'
import ViewLinks from './ViewLinks'

export default connect(
  ({ viewLinks }) => ({ ...viewLinks }),
  dispatch => bindActionCreators(actions, dispatch),
)(ViewLinks)
