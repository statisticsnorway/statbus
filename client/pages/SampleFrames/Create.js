import { bindActionCreators } from 'redux'
import { connect } from 'react-redux'
import { pipe } from 'ramda'
import { defaultProps } from 'recompose'

import createSchemaFormHoc from '/client/components/createSchemaFormHoc'
import { getText } from '/client/helpers/locale'
import { create as actions } from './actions'
import FormBody from './FormBody'
import { createDefaults, schema } from './model'

const stateToProps = state => ({
  localize: getText(state.locale),
  locale: state.locale,
})

const { postSampleFrame, navigateBack } = actions
const dispatchToProps = dispatch =>
  bindActionCreators(
    {
      onSubmit: postSampleFrame,
      onCancel: navigateBack,
    },
    dispatch,
  )

export default pipe(
  createSchemaFormHoc(schema),
  defaultProps({
    values: createDefaults(),
    validateOnBlur: false,
    validateOnChange: false,
  }),
  connect(stateToProps, dispatchToProps),
)(FormBody)
