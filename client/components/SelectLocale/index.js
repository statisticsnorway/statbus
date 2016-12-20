import { connect } from 'react-redux'

import { actionCreator } from 'helpers/locale'
import SelectLocale from './SelectLocale'

export default connect(
  ({ locale }) => ({ locale }),
  dispatch => ({ selectLocale: locale => dispatch(actionCreator(locale)) }),
)(SelectLocale)
