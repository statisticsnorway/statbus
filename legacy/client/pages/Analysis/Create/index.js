import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { equals, pipe } from 'ramda'

import { getText } from '/helpers/locale'
import { create } from '../actions.js'
import Create from './Create.jsx'

const mapStateToProps = state => ({
  ...state.analysis.create,
  localize: getText(state.locale),
})

const mapDispatchToProps = dispatch => ({
  actions: {
    ...bindActionCreators(create, dispatch),
  },
})

const hooks = {
  shouldComponentUpdate(nextProps, nextState) {
    return (
      this.props.localize.lang !== nextProps.localize.lang ||
      !equals(this.props, nextProps) ||
      !equals(this.state, nextState)
    )
  },

  componentWillUnmount() {
    this.props.actions.clear()
  },
}

export default pipe(lifecycle(hooks), connect(mapStateToProps, mapDispatchToProps))(Create)
