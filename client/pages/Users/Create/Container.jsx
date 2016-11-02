import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import actions from './actions'
import Create from './Create'

export default connect(
  ({ createUser }) => ({ ...createUser }),
  dispatch => bindActionCreators(actions, dispatch)
)(Create)
