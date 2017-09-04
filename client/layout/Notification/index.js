import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { notification as actionCreators } from 'helpers/actionCreators'
import Notification from './Notification'

export default connect(
  ({ notification }) => notification,
  dispatch => bindActionCreators(actionCreators, dispatch),
)(Notification)
