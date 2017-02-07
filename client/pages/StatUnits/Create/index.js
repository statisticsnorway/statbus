import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import CreateStatUnitPage from './CreateStatUnitPage'
import * as createActions from './actions'

export default connect(
  ({ createStatUnit: { statUnitModel, type, errors } }) => ({
    statUnitModel,
    type,
    errors,
  }),
  dispatch => ({
    actions: bindActionCreators(createActions, dispatch),
  }))(CreateStatUnitPage)
