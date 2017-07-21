import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions'
import CreateLink from './CreateLink'

export default connect(
  ({ editLinks }, { router: { location: { query: params } } }) => ({ ...editLinks, params }),
  dispatch => bindActionCreators(actions, dispatch),
)(CreateLink)
