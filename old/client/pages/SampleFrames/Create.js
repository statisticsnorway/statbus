import { bindActionCreators } from 'redux'
import { connect } from 'react-redux'
import { pipe } from 'ramda'
import { defaultProps } from 'recompose'

import createSchemaFormHoc from '/components/createSchemaFormHoc'
import { getText } from '/helpers/locale'
import { create as actions } from './actions.js'
import FormBody from './FormBody.jsx'
import { createDefaults, schema } from './model.js'

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
