import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { actions } from 'helpers/notification'
import Notification from './Notification'

export default connect(
  ({ notification }) => ({ ...notification }),
  dispatch => bindActionCreators(actions, dispatch),
)(Notification)
