import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import { edit as editActions } from './actions'
import DataSourceTemplateForm from './TemplateForm'

const { submitData, fetchColumns, fetchDataSource } = editActions
export default connect(
  state => ({
    columns: state.dataSources.columns,
    localize: getText(state.locale),
  }),
  (dispatch, props) => {
    const id = props.router.location.query.id
    return {
      submitData: bindActionCreators(submitData(id), dispatch),
      onMount: () => {
        dispatch(fetchDataSource(id))
        dispatch(fetchColumns())
      },
    }
  },
)(DataSourceTemplateForm)
