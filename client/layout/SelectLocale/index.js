import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { selectLocale } from '/client/helpers/actionCreators'
import SelectLocale from './SelectLocale'

export default connect(
  ({ locale }) => ({ locale }),
  dispatch => bindActionCreators({ selectLocale }, dispatch),
)(SelectLocale)
