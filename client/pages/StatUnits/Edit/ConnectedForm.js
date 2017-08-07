import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import StatUnitForm from 'components/StatUnitForm'
import { getText } from 'helpers/locale'
import { actionCreators } from './actions'

const { editForm } = actionCreators

export default connect(
  ({ editStatUnit: { statUnit, type, errors, schema }, locale }, ownProps) => ({
    statUnit,
    errors,
    schema,
    localize: getText(locale),
    ...ownProps,
  }),
  dispatch => bindActionCreators({ onChange: editForm }, dispatch),
)(StatUnitForm)
