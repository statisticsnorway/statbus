import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import * as editActions from './actions'
import EditStatUnitPage from './EditStatUnitPage'

export default connect(
  ({ editStatUnit: { statUnit, errors } },
    { params }) => ({
      statUnit,
      errors,
      id: params.id,
      type: params.type,
    }),
  dispatch => ({
    actions: bindActionCreators(editActions, dispatch),
  }),
)(EditStatUnitPage)
