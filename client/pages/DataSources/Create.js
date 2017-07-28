import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { not, isEmpty, values, any, anyPass, isNil, pipe } from 'ramda'

import withOnMount from 'components/withOnMount'
import withSpinnerUnless from 'components/withSpinnerUnless'
import { getText } from 'helpers/locale'
import { create as createActions } from './actions'
import TemplateForm from './TemplateForm'

const { fetchColumns, ...actions } = createActions

const nonEmpty = pipe(anyPass([isNil, isEmpty]), not)
const nonEmptyValues = pipe(values, any(nonEmpty), not)

const assert = ({ columns }) =>
  nonEmpty(columns) && nonEmptyValues(columns)

export default pipe(
  withSpinnerUnless(assert),
  withOnMount,
  connect(
    state => ({
      columns: state.dataSources.columns,
      localize: getText(state.locale),
    }),
    dispatch => ({
      ...bindActionCreators(actions, dispatch),
      onMount: () => dispatch(fetchColumns()),
    })),
)(TemplateForm)
