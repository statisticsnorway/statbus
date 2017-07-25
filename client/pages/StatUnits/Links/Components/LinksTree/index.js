import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions'
import LinksTree from './LinksTree'

export default connect(
  (_, ownProps) => ownProps,
  dispatch => bindActionCreators(actions, dispatch),
)(LinksTree)
