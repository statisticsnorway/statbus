import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import actions from './actions'
import EditForm from './EditForm'

export default connect(
  ({ editStatUnit: { statUnit } }, { editForm, submitStatUnit, params }) => ({
    statUnit,
    editForm,
    submitStatUnit,
    id: params.id,
  }),
  dispatch => bindActionCreators(actions, dispatch),
)(EditForm)
