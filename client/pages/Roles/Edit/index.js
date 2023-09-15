import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from '/client/helpers/locale'
import actions from './actions'
import Edit from './Edit'

export default connect(
  (state, props) => ({
    ...state.editRole,
    ...props.params,
    localize: getText(state.locale),
  }),
  dispatch => bindActionCreators(actions, dispatch),
)(Edit)
