import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { anyPass, isNil, not, isEmpty, values, any, pipe } from 'ramda'

import withOnMount from 'components/withOnMount'
import withSpinnerUnless from 'components/withSpinnerUnless'
import { getText } from 'helpers/locale'
import { edit as editActions } from './actions'
import TemplateForm from './TemplateForm'

const { submitData, fetchColumns, fetchDataSource } = editActions

const nonEmpty = pipe(anyPass([isNil, isEmpty]), not)
const nonEmptyValues = pipe(values, any(nonEmpty))

const assert = ({ formData, columns }) =>
  nonEmpty(formData) && nonEmpty(columns) && nonEmptyValues(columns)

export default pipe(
  withSpinnerUnless(assert),
  withOnMount,
  connect(
    state => ({
      formData: state.dataSources.editFormData,
      columns: state.dataSources.columns,
      localize: getText(state.locale),
    }),
    (dispatch, props) => ({
      submitData: bindActionCreators(submitData(props.params.id), dispatch),
      onMount: () => {
        dispatch(fetchDataSource(props.params.id))
        dispatch(fetchColumns())
      },
    }),
  ),
)(TemplateForm)
