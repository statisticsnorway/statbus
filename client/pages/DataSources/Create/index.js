import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import { create as actions } from '../actions'
import Create from './Create'

export default connect(
  ({ locale, dataSources: { columns } }) => ({
    columns,
    localize: getText(locale),
  }),
  dispatch => ({
    actions: bindActionCreators(actions, dispatch),
  }),
)(Create)
