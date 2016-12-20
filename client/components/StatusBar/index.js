import { connect } from 'react-redux'

import { actions as rqstActions } from 'helpers/requestStatus'
import StatusBar from './StatusBar'

export default connect(
  ({ status }) => ({ ...status }),
  dispatch => ({ dismiss: () => dispatch(rqstActions.dismiss()) }),
)(StatusBar)
