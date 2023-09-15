import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { notification as actionCreators } from '/client/helpers/actionCreators'
import { getText } from '/client/helpers/locale'
import Notification from './Notification'

export default connect(
  state => ({ ...state.notification, localize: getText(state.locale) }),
  dispatch => bindActionCreators(actionCreators, dispatch),
)(Notification)
