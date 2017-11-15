import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { pipe } from 'ramda'
import { lifecycle } from 'recompose'

import createSchemaFormHoc from 'components/createSchemaFormHoc'
import withSpinnerUnless from 'components/withSpinnerUnless'
import { getText } from 'helpers/locale'
import { hasValue, hasValues } from 'helpers/validation'
import { edit as actions, clear } from './actions'
import { createSchema } from './model'
import FormBody from './FormBody'

const propsToSchema = props => createSchema(props.columns)

const assert = ({ values, columns }) => hasValue(values) && hasValues(columns)

const { fetchDataSource, fetchColumns, onSubmit, onCancel } = actions

const hooks = {
  componentDidMount() {
    this.props.fetchColumns()
  },
  componentWillReceiveProps(nextProps) {
    if (!hasValues(this.props.columns) && hasValues(nextProps.columns)) {
      this.props.fetchDataSource(nextProps.columns)
    }
  },
  componentWillUnmount() {
    this.props.clear()
  },
}

const stateToProps = state => ({
  values: state.dataSources.editFormData,
  columns: state.dataSources.columns,
  localize: getText(state.locale),
})

const dispatchToProps = (dispatch, props) =>
  bindActionCreators(
    {
      fetchColumns,
      fetchDataSource: columns => fetchDataSource(props.params.id, columns),
      onSubmit: onSubmit(props.params.id),
      onCancel,
      clear,
    },
    dispatch,
  )

export default pipe(
  createSchemaFormHoc(propsToSchema),
  withSpinnerUnless(assert),
  lifecycle(hooks),
  connect(stateToProps, dispatchToProps),
)(FormBody)
