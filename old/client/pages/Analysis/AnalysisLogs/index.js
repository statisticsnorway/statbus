import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { equals, pipe } from 'ramda'

import { getText } from '/helpers/locale'
import { logs } from '../actions.js'
import Logs from './Logs.jsx'

const mapStateToProps = (state, props) => ({
  ...state.analysis.logs,
  localize: getText(state.locale),
  query: props.location.query,
})

const { fetchAnalysisLogs, ...actions } = logs
const mapDispatchToProps = (dispatch, props) => ({
  actions: {
    ...bindActionCreators(actions, dispatch),
    fetchAnalysisLogs: q => dispatch(fetchAnalysisLogs(props.params.queueId)(q)),
  },
})

const hooks = {
  componentDidMount() {
    this.props.actions.fetchAnalysisLogs(this.props.query)
  },

  componentWillReceiveProps(nextProps) {
    if (!equals(nextProps.query, this.props.query)) {
      nextProps.actions.fetchAnalysisLogs(nextProps.query)
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
    // this.props.actions.clear()
  },
}

export default pipe(lifecycle(hooks), connect(mapStateToProps, mapDispatchToProps))(Logs)
