import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { pipe, merge, equals } from 'ramda'

import withSpinnerUnless from 'components/withSpinnerUnless'
import { getText } from 'helpers/locale'
import { list as actions } from '../actions'
import List from './List'

const assertProps = props => props.result != null

const hooks = {
  componentDidMount() {
    this.props.getSampleFrames(this.props.query)
  },
  componentWillReceiveProps(nextProps) {
    if (!equals(nextProps.query, this.props.query)) {
      nextProps.getSampleFrames(nextProps.query)
    }
  },
  componentWillUnmount() {
    this.props.clearSearchForm()
  },
}

const mapStateToProps = (state, props) => ({
  ...state.sampleFrames.list,
  query: props.location.query,
  localize: getText(state.locale),
})

const { setQuery, ...restActions } = actions
const mapDispatchToProps = (dispatch, props) => ({
  ...bindActionCreators(restActions, dispatch),
  setQuery: pipe(merge(props.location.query), setQuery(props.location.pathname), dispatch),
})

export default pipe(
  withSpinnerUnless(assertProps),
  lifecycle(hooks),
  connect(mapStateToProps, mapDispatchToProps),
)(List)
