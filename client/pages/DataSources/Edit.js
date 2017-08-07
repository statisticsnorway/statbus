import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { pipe } from 'ramda'
import { lifecycle } from 'recompose'

import withSpinnerUnless from 'components/withSpinnerUnless'
import { getText } from 'helpers/locale'
import { nonEmpty, nonEmptyValues } from 'helpers/schema'
import { edit as editActions, clear } from './actions'
import TemplateForm from './TemplateForm'

const { submitData, fetchColumns, fetchDataSource } = editActions

const assert = ({ formData, columns }) =>
  nonEmpty(formData) && nonEmpty(columns) && nonEmptyValues(columns)

const hooks = {
  componentDidMount() {
    this.props.fetchDataSource()
    this.props.fetchColumns()
  },
  componentWillUnmount() {
    this.props.clear()
  },
}

export default pipe(
  withSpinnerUnless(assert),
  lifecycle(hooks),
  connect(
    state => ({
      formData: state.dataSources.editFormData,
      columns: state.dataSources.columns,
      localize: getText(state.locale),
    }),
    (dispatch, props) => bindActionCreators(
      {
        clear,
        fetchColumns,
        fetchDataSource: () => fetchDataSource(props.params.id),
        submitData: submitData(props.params.id),
      },
      dispatch,
    ),
  ),
)(TemplateForm)
