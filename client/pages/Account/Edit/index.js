import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import actions from './actions'
import Edit from './EditDetails'

export default connect(
  ({ locale }) => ({ localize: getText(locale) }),
  dispatch => bindActionCreators(actions, dispatch),
)(Edit)
