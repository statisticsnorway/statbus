import { bindActionCreators } from 'redux'
import { connect } from 'react-redux'
import { pipe, prop } from 'ramda'
import { lifecycle } from 'recompose'

import createSchemaFormHoc from '/components/createSchemaFormHoc'
import withSpinnerUnless from '/components/withSpinnerUnless'
import { getText } from '/helpers/locale'
import { edit as actions } from './actions.js'
import FormBody from './FormBody.jsx'
import { schema } from './model.js'

const stateToProps = state => ({
  ...state.sampleFrames.edit,
  localize: getText(state.locale),
  locale: state.locale,
})

const { putSampleFrame, navigateBack, getSampleFrame, ...restActions } = actions
const dispatchToProps = (dispatch, props) =>
  bindActionCreators(
    {
      ...restActions,
      getSampleFrame: () => getSampleFrame(props.params.id),
      onSubmit: (...params) => putSampleFrame(props.params.id, ...params),
      onCancel: navigateBack,
    },
    dispatch,
  )

const hooks = {
  componentDidMount() {
    this.props.getSampleFrame(this.props.id)
  },
  componentWillUnmount() {
    this.props.clearEditForm()
  },
}

const assert = props => props.formData != null

export default pipe(
  createSchemaFormHoc(schema, prop('formData')),
  withSpinnerUnless(assert),
  lifecycle(hooks),
  connect(stateToProps, dispatchToProps),
)(FormBody)
