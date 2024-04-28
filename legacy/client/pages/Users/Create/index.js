import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from '/helpers/locale'
import actions from './actions.js'
import Create from './Create.jsx'

export default connect(
  ({ createUser, locale, users: { loginError } }) => ({
    ...createUser,
    localize: getText(locale),
    loginError,
  }),
  dispatch => bindActionCreators(actions, dispatch),
)(Create)
