// @flow
import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { pipe } from 'ramda'

import { getText } from 'helpers/locale'
import { actionCreators } from './actions'
import Create from './Create'

const hooks = {
  componentDidMount() {
    this.props.fetchModel(this.props.type)
  },
  componentWillReceiveProps(nextProps) {
    if (this.props.type !== nextProps.type) {
      nextProps.fetchModel(nextProps.type)
    }
  },
}

const mapStateToProps = (state, props) => ({
  type: props.params.type,
  localize: getText(state.locale),
})
const mapDispatchToProps = dispatch => bindActionCreators(actionCreators, dispatch)

export default pipe(
  lifecycle(hooks),
  connect(
    mapStateToProps,
    mapDispatchToProps,
  ),
)(Create)
