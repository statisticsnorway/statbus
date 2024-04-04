import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { notification as actionCreators } from '/helpers/actionCreators'
import { getText } from '/helpers/locale'
import Notification from './Notification.jsx'

export default connect(
  state => ({ ...state.notification, localize: getText(state.locale) }),
  dispatch => bindActionCreators(actionCreators, dispatch),
)(Notification)
