import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions'
import DeletedList from './DeletedList'

export default connect(
  (state, { params, location: { query, pathname } }) => ({
    state: state.deletedStatUnits,
    route: { pararms, query, pathname },
  }),
  dispatch => bindActionCreators(actions, dispatch),
)(DeletedList)
