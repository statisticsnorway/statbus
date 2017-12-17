import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { pipe } from 'ramda'
import { defaultProps, lifecycle } from 'recompose'

import createSchemaFormHoc from 'components/createSchemaFormHoc'
import withSpinnerUnless from 'components/withSpinnerUnless'
import { getText } from 'helpers/locale'
import { hasValue, hasValues } from 'helpers/validation'
import { create as actions } from './actions'
import { defaults, createSchema } from './model'
import FormBody from './FormBody'

const propsToSchema = props => createSchema(props.columns)

const assert = ({ columns }) => hasValue(columns) && hasValues(columns)

const hooks = {
  componentDidMount() {
    this.props.fetchColumns()
  },
}

const stateToProps = state => ({
  columns: state.dataSources.columns,
  localize: getText(state.locale),
})

const dispatchToProps = dispatch => bindActionCreators(actions, dispatch)

export default pipe(
  createSchemaFormHoc(propsToSchema),
  defaultProps({ values: defaults }),
  withSpinnerUnless(assert),
  lifecycle(hooks),
  connect(stateToProps, dispatchToProps),
)(FormBody)
