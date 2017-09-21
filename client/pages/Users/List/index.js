import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import actions from './actions'
import List from './List'

export default connect(
  state => ({
    ...state.users,
    localize: getText(state.locale),
  }),
  dispatch => bindActionCreators(actions, dispatch),
)(List)
