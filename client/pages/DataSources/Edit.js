import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import { edit as actions } from './actions'
import DataSourceTemplateForm from './DataSourceTemplateForm'

const { submitData, ...otherActions } = actions
export default connect(
  state => ({
    columns: state.dataSources.columns,
    localize: getText(state.locale),
  }),
  (dispatch, props) => ({
    actions: bindActionCreators(
      {
        ...otherActions,
        submitData: submitData(props.routes.query.id),
      },
      dispatch),
  }),
)(DataSourceTemplateForm)
