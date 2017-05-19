import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import { actionCreators } from './actions'
import Create from './Create'

const { editForm, ...rest } = actionCreators

export default connect(
  ({ createStatUnit: { type }, locale }) => ({
    type,
    localize: getText(locale),
  }),
  dispatch => ({
    actions: bindActionCreators(rest, dispatch),
  }),
)(Create)
