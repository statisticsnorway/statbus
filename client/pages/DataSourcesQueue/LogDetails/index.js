import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { pipe } from 'ramda'
import { lifecycle } from 'recompose'

import withSpinnerUnless from '/client/components/withSpinnerUnless'
import { getText } from '/client/helpers/locale'
import { hasValue } from '/client/helpers/validation'
import { details } from '../actions'
import Page from './Page'

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
