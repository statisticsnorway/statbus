import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { not, isEmpty, values, any, anyPass, isNil, pipe } from 'ramda'
import { lifecycle } from 'recompose'

import withSpinnerUnless from 'components/withSpinnerUnless'
import { getText } from 'helpers/locale'
import { create as actions } from './actions'
import TemplateForm from './TemplateForm'

const nonEmpty = pipe(anyPass([isNil, isEmpty]), not)
const nonEmptyValues = pipe(values, any(nonEmpty))

const assert = ({ columns }) =>
  nonEmpty(columns) && nonEmptyValues(columns)

const hooks = {
  componentDidMount() {
    this.props.fetchColumns()
  },
}

export default pipe(
  withSpinnerUnless(assert),
  lifecycle(hooks),
  connect(
    state => ({
      columns: state.dataSources.columns,
      localize: getText(state.locale),
    }),
    dispatch => bindActionCreators(actions, dispatch),
  ),
)(TemplateForm)
