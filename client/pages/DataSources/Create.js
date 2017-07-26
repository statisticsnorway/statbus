import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import { create as actions } from './actions'
import Form from './DataSourceTemplateForm'

export default connect(
  state => ({
    columns: state.dataSources.columns,
    localize: getText(state.locale),
  }),
  dispatch => ({
    actions: bindActionCreators(actions, dispatch),
  }),
)(Form)
