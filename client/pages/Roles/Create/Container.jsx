import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import actions from './actions'
import Create from './Create'

export default connect(
  ({ createRole }) => ({ ...createRole }),
  dispatch => bindActionCreators(actions, dispatch),
)(Create)
