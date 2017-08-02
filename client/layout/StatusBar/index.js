import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import { actions as rqstActions } from 'helpers/requestStatus'
import StatusBar from './StatusBar'

const { dismiss, dismissAll } = rqstActions
export default connect(
  ({ status, locale }) => ({ status, localize: getText(locale) }),
  dispatch => bindActionCreators({ dismiss, dismissAll }, dispatch),
)(StatusBar)
