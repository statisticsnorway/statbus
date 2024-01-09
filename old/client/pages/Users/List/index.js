import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from '/helpers/locale'
import actions from './actions.js'
import List from './List.jsx'

export default connect(
  state => ({
    ...state.users,
    localize: getText(state.locale),
  }),
  dispatch => bindActionCreators(actions, dispatch),
)(List)
