import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from '/client/helpers/locale'
import actions from './actions'
import Create from './Create'

export default connect(
  ({ createUser, locale, users: { loginError } }) => ({
    ...createUser,
    localize: getText(locale),
    loginError,
  }),
  dispatch => bindActionCreators(actions, dispatch),
)(Create)
