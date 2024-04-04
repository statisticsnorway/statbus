import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { equals, pipe } from 'ramda'

import { hasValue } from '/helpers/validation'
import { getText } from '/helpers/locale'
import { log } from '../actions.js'
import QueueLog from './QueueLog.jsx'

const { clear, fetchLog, deleteLog } = log
const mapStateToProps = (state, props) => ({
  ...state.dataSourcesQueue.log,
  query: props.location.query,
  localize: getText(state.locale),
})

const mapDispatchToProps = (dispatch, props) =>
  bindActionCreators(
    {
      clear,
      fetchLog: fetchLog(props.params.id),
      deleteLog,
    },
    dispatch,
  )

const hooks = {
  componentDidMount() {
    this.props.fetchLog(this.props.query)
  },

  componentWillReceiveProps(nextProps) {
    if (!equals(nextProps.query, this.props.query)) {
      nextProps.fetchLog(nextProps.query)
    }
  },

  shouldComponentUpdate(nextProps, nextState) {
    return (
      this.props.localize.lang !== nextProps.localize.lang ||
      !equals(this.props, nextProps) ||
      !equals(this.state, nextState)
    )
  },

  componentDidUpdate(prevProps) {
    const isEmptyResult = hasValue(this.props.result)
    const prevIsEmptyResult = hasValue(prevProps.result)
    if (!isEmptyResult && prevIsEmptyResult) {
      this.props.router.push('/datasourcesqueue/')
    }
  },

  componentWillUnmount() {
    this.props.clear()
  },
}

export default pipe(lifecycle(hooks), connect(mapStateToProps, mapDispatchToProps))(QueueLog)
