import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions'
import List from './DeletedList'

export default connect(

  dispatch => bindActionCreators(actions, dispatch),
)(List)
