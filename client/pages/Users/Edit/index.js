import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import actions from './actions'
import { checkExistLogin, checkExistLoginSuccess } from '../Create/actions'
import Edit from './Edit'

const editActions = { ...actions, checkExistLogin, checkExistLoginSuccess }

export default connect(
  ({ editUser, locale, users: { loginError } }, { params }) => ({
    ...editUser,
    ...params,
    localize: getText(locale),
    loginError,
  }),
  dispatch => bindActionCreators(editActions, dispatch),
)(Edit)
