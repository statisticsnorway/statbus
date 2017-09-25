import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import actions from './actions'
import Create from './Create'

export default connect(
  state => ({
    ...state.createAddress,
    localize: getText(state.locale),
  }),
  dispatch => bindActionCreators(actions, dispatch),
)(Create)
