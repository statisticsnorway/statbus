import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions.js'
import LinksTree from './LinksTree.jsx'

export default connect(
  (_, ownProps) => ownProps,
  dispatch => bindActionCreators(actions, dispatch),
)(LinksTree)
