import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { list as actions } from '../actions'
import List from './List'

export default connect(
  state => state.dataSources,
  dispatch => ({ actions: bindActionCreators(actions, dispatch) }),
)(List)
