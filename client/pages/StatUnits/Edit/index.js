import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import { actionCreators } from './actions'
import Edit from './Edit'

const { editForm, ...rest } = actionCreators

export default connect(
  ({ locale }, { params: { id, type } }) => ({
    regId: id,
    type,
    localize: getText(locale),
  }),
  dispatch => ({
    actions: bindActionCreators(rest, dispatch),
  }),
)(Edit)
