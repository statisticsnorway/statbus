import { connect } from 'react-redux'

import StatusBar from './StatusBar'
import { actions as rqstActions } from 'helpers/requestStatus'

export default connect(
  ({ status }) => ({ ...status }),
  dispatch => ({ dismiss: () => dispatch(rqstActions.dismiss()) }),
)(StatusBar)
