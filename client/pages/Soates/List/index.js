import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions'
import List from './List'

export default connect(
   ({ soates }, { location: { query } }) => ({ ...soates, query }),
  dispatch => bindActionCreators(actions, dispatch),
)(List)
