import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { actions } from 'helpers/notification'
import Notification from './Notification'

export default connect(
  ({ notification: { open, text } }) => ({ open, text }),
  dispatch => bindActionCreators(actions, dispatch),
)(Notification)
