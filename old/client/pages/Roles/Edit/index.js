import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from '/helpers/locale'
import actions from './actions.js'
import Edit from './Edit.jsx'

export default connect(
  (state, props) => ({
    ...state.editRole,
    ...props.params,
    localize: getText(state.locale),
  }),
  dispatch => bindActionCreators(actions, dispatch),
)(Edit)
