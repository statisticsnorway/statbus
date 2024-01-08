import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from '/helpers/locale'

import actions from './actions.js'
import Create from './Create.jsx'

export default connect(
  state => ({
    ...state.createRole,
    localize: getText(state.locale),
  }),
  dispatch => bindActionCreators(actions, dispatch),
)(Create)
