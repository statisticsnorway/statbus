import { bindActionCreators } from 'redux'
import { connect } from 'react-redux'
import { pipe } from 'ramda'
import { defaultProps } from 'recompose'

import createSchemaFormHoc from 'components/createSchemaFormHoc'
import { getText } from 'helpers/locale'
import { create as actions } from './actions'
import FormBody from './FormBody'
import { createDefaults, schema } from './model'

const stateToProps = state => ({ localize: getText(state.locale) })

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
  defaultProps({ values: createDefaults() }),
  connect(stateToProps, dispatchToProps),
)(FormBody)
