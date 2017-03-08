import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions'
import DeletedList from './DeletedList'

export default connect(
  (state, { location: { query } }) => ({ ...state.deletedStatUnits, query }),
  dispatch => ({ actions: bindActionCreators(actions, dispatch) }),
)(DeletedList)
