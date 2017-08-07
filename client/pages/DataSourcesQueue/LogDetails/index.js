import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { pipe } from 'ramda'

import withSpinnerUnless from 'components/withSpinnerUnless'
import { nonEmpty } from 'helpers/schema'
import { details } from '../actions'
import Form from './Form'

const { fetchLogEntry, submitLogEntry, clear } = details

const mapStateToProps = state => state.dataSourcesQueue.details

const mapDispatchToProps = (dispatch, props) =>
  bindActionCreators(
    {
      fetchData: () => fetchLogEntry(props.params.id),
      submitData: submitLogEntry(props.params.id, props.params.queueId),
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

const assert = props => !props.fetching && nonEmpty(props.formData)

export default pipe(
  withSpinnerUnless(assert),
  lifecycle(hooks),
  connect(mapStateToProps, mapDispatchToProps),
)(Form)
