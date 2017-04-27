import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions'
import Control from './LinksTree'

export default connect(
  () => ({}),
  dispatch => bindActionCreators(actions, dispatch),
)(Control)
