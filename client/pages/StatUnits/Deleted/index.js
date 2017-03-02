import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions'
import DeletedList from './DeletedList'

export default connect(
  state => state.deletedStatUnits,
  dispatch => bindActionCreators(actions, dispatch),
)(DeletedList)
