import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import actions from './actions'
import Edit from './Edit'

export default connect(
  ({ editAddress, locale }, { params }) => ({
    ...editAddress,
    ...params,
    localize: getText(locale),
  }),
  dispatch => bindActionCreators(actions, dispatch),
)(Edit)
