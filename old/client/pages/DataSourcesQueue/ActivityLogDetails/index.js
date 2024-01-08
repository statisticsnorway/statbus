import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { pipe } from 'ramda'
import { lifecycle } from 'recompose'

import withSpinnerUnless from '/components/withSpinnerUnless'
import { getText } from '/helpers/locale'
import { details } from '../actions.js'
import Page from './Page.jsx'

const { fetchActivitiesDetails, clear } = details

const mapStateToProps = (state, props) => ({
  statId: props.params.logId,
  queueId: props.params.queueId,
  details: state.dataSourcesQueue.activitiesDetails,
  localize: getText(state.locale),
})

const mapDispatchToProps = (dispatch, props) =>
  bindActionCreators(
    {
      fetchData: () => fetchActivitiesDetails(props.params.queueId, props.params.statId),
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

const assert = props => !props.details.fetching

export default pipe(
  withSpinnerUnless(assert),
  lifecycle(hooks),
  connect(mapStateToProps, mapDispatchToProps),
)(Page)
