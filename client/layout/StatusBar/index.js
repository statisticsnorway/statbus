import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import { request as actionCreators } from 'helpers/actionCreators'
import StatusBar from './StatusBar'

const { dismiss, dismissAll } = actionCreators
export default connect(
  ({ status, locale }) => ({ status, localize: getText(locale) }),
  dispatch => bindActionCreators({ dismiss, dismissAll }, dispatch),
)(StatusBar)
