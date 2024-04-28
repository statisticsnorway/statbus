import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { equals, pipe } from 'ramda'

import { getText } from '/helpers/locale'
import { queue } from '../actions.js'
import Queue from './Queue.jsx'

const mapStateToProps = (state, props) => ({
  ...state.analysis.queue,
  query: props.location.query,
  localize: getText(state.locale),
})

const { setQuery, ...actions } = queue

const mapDispatchToProps = (dispatch, props) => ({
  actions: {
    ...bindActionCreators(actions, dispatch),
    setQuery: bindActionCreators(setQuery(props.location.pathname), dispatch),
  },
})

const hooks = {
  componentDidMount() {
    this.props.actions.fetchQueue(this.props.query)
  },

  componentWillReceiveProps(nextProps) {
    if (!equals(nextProps.query, this.props.query)) {
      nextProps.actions.fetchQueue(nextProps.query)
    }
  },

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

export default pipe(lifecycle(hooks), connect(mapStateToProps, mapDispatchToProps))(Queue)
