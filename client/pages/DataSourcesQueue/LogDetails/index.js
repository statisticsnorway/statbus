import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle, compose } from 'recompose'

import { details } from '../actions'
import Form from './Form'

const mapStateToProps = (state, props) => ({})

const mapDispatchToProps = (dispatch, props) =>
  bindActionCreators(details, dispatch)

const hooks = {}

export default compose(
  connect(mapStateToProps, mapDispatchToProps),
  lifecycle(hooks),
)(Form)
