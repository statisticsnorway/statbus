import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from '/helpers/locale'
import actions from './actions.js'
import Authentication from './Authentication.jsx'

export default connect(
  state => ({ ...state.authentication, localize: getText(state.locale) }),
  dispatch => bindActionCreators(actions, dispatch),
)(Authentication)
