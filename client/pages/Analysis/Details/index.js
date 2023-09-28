import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { pipe } from 'ramda'
import { lifecycle } from 'recompose'

import withSpinnerUnless from '/client/components/withSpinnerUnless'
import { getText } from '/client/helpers/locale'
import { hasValue } from '/client/helpers/validation'
import { details as actions } from '../actions'
import Page from './Page'

const withSpinner = withSpinnerUnless(props => !props.fetching && hasValue(props.logEntry))

const withLifecycle = lifecycle({
  componentDidMount() {
    this.props.fetchDetails(this.props.logId)
  },
  componentWillUnmount() {
    this.props.clearDetails()
  },
})

const withConnect = connect(
  (state, props) => ({
    logId: props.params.logId,
    queueId: props.params.queueId,
    logEntry: state.analysis.details.logEntry,
    fetching: state.analysis.details.fetching,
    localize: getText(state.locale),
  }),
  dispatch =>
    bindActionCreators(
      {
        fetchDetails: actions.fetchDetails,
        clearDetails: actions.clearDetails,
      },
      dispatch,
    ),
)

const enhance = pipe(withSpinner, withLifecycle, withConnect)

export default enhance(Page)
