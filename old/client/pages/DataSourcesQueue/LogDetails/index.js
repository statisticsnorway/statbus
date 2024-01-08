import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { pipe } from 'ramda'
import { lifecycle } from 'recompose'

import withSpinnerUnless from '/components/withSpinnerUnless'
import { getText } from '/helpers/locale'
import { hasValue } from '/helpers/validation'
import { details } from '../actions.js'
import Page from './Page.jsx'

const { fetchLogEntry, clear } = details

const mapStateToProps = (state, props) => ({
  logId: props.params.logId,
  queueId: props.params.queueId,
  info: state.dataSourcesQueue.details.info,
  errors: state.dataSourcesQueue.details.errors,
  localize: getText(state.locale),
})

const mapDispatchToProps = (dispatch, props) =>
  bindActionCreators(
    {
      fetchData: () => fetchLogEntry(props.params.logId),
      clear,
    },
    dispatch,
  )

const hooks = {
  componentDidMount() {
    this.props.fetchData()
  },
  componentWillUnmount() {
    this.props.clear()
  },
}

const assert = props => !props.fetching && hasValue(props.info)

export default pipe(
  withSpinnerUnless(assert),
  lifecycle(hooks),
  connect(mapStateToProps, mapDispatchToProps),
)(Page)
