import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { pipe } from 'ramda'
import { lifecycle } from 'recompose'

import createSchemaFormHoc from 'components/createSchemaFormHoc'
import withSpinnerUnless from 'components/withSpinnerUnless'
import { getText } from 'helpers/locale'
import { hasValue, hasValues } from 'helpers/validation'
import { edit as actions, clear } from './actions'
import { schema } from './model'
import FormBody from './FormBody'

const { fetchDataSource, fetchColumns, onSubmit, onCancel } = actions

const assert = ({ values, columns }) =>
  hasValue(values) && hasValue(columns) && hasValues(columns)

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
  createSchemaFormHoc(schema),
  withSpinnerUnless(assert),
  lifecycle(hooks),
  connect(
    state => ({
      values: state.dataSources.editFormData,
      columns: state.dataSources.columns,
      localize: getText(state.locale),
    }),
    (dispatch, props) => bindActionCreators(
      {
        fetchColumns,
        fetchDataSource: () => fetchDataSource(props.params.id),
        onSubmit: onSubmit(props.params.id),
        onCancel,
        clear,
      },
      dispatch,
    ),
  ),
)(FormBody)
