import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { pipe } from 'ramda'
import { defaultProps, lifecycle } from 'recompose'

import createSchemaFormHoc from 'components/createSchemaFormHoc'
import withSpinnerUnless from 'components/withSpinnerUnless'
import { getText } from 'helpers/locale'
import { hasValue, hasValues } from 'helpers/schema'
import { create as actions } from './actions'
import { schema } from './model'
import FormBody from './FormBody'

const assert = ({ columns }) =>
  hasValue(columns) && hasValues(columns)

const hooks = {
  componentDidMount() {
    this.props.fetchColumns()
  },
}

export default pipe(
  createSchemaFormHoc(schema),
  defaultProps({ values: schema.default() }),
  withSpinnerUnless(assert),
  lifecycle(hooks),
  connect(
    state => ({
      columns: state.dataSources.columns,
      localize: getText(state.locale),
    }),
    dispatch => bindActionCreators(actions, dispatch),
  ),
)(FormBody)
