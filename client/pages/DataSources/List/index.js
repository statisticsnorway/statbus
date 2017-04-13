import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { list as actions } from '../actions'
import List from './List'

export default connect(
  ({ dataSources: state }) => ({
    dataSources: state.items,
    totalCount: state.totalCount,
  }),
  dispatch => ({ actions: bindActionCreators(actions, dispatch) }),
)(List)
