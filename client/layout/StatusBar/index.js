import { connect } from 'react-redux'

import { actions as rqstActions } from 'helpers/requestStatus'
import StatusBar from './StatusBar'

export default connect(
  ({ status }) => ({ status }),
  dispatch => ({
    dismiss: id => dispatch(rqstActions.dismiss(id)),
    dismissAll: () => dispatch(rqstActions.dismissAll()),
  }),
)(StatusBar)
