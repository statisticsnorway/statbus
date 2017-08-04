import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { pipe } from 'ramda'

import { details } from '../actions'
import Form from './Form'

const mapStateToProps = (state, props) => ({})

const mapDispatchToProps = (dispatch, props) =>
  bindActionCreators(details, dispatch)

const hooks = {}

export default pipe(
  lifecycle(hooks),
  connect(mapStateToProps, mapDispatchToProps),
)(Form)
