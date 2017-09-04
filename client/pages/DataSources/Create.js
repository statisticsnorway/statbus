import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { pipe } from 'ramda'
import { lifecycle } from 'recompose'

import withSpinnerUnless from 'components/withSpinnerUnless'
import { getText } from 'helpers/locale'
import { nonEmpty, nonEmptyValues } from 'helpers/schema'
import { create as actions } from './actions'
import TemplateForm from './TemplateForm'

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
