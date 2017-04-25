import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions'
import List from './List'

export default connect(
  ({ roles }, { location: { query } }) => ({ ...roles, query }),
  dispatch => bindActionCreators(actions, dispatch),
)(List)
