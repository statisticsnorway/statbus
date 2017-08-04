import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { pipe, isEmpty } from 'ramda'

import withSpinnerUnless from 'components/withSpinnerUnless'
import { details } from '../actions'
import Form from './Form'

const { fetchLogEntry, submitLogEntry, clear } = details

const mapStateToProps = state => state.dataSourcesQueue.details

const mapDispatchToProps = (dispatch, props) =>
  bindActionCreators(
    {
      fetchData: () => fetchLogEntry(props.params.id),
      submitLogEntry: submitLogEntry(props.params.id),
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

const assert = props => (console.log('assert', props, !props.fetching && !isEmpty(props.formData)), !props.fetching && !isEmpty(props.formData))

export default pipe(
  withSpinnerUnless(assert),
  lifecycle(hooks),
  connect(mapStateToProps, mapDispatchToProps),
)(Form)
