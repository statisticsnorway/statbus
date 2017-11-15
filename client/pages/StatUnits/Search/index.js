import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { pipe, equals } from 'ramda'

import { getText } from 'helpers/locale'
import actionCreators from './actions'
import SearchStatUnit from './SearchStatUnit'

const { setQuery, ...actions } = actionCreators

const hooks = {
  componentDidMount() {
    if (this.props.queryString === '') return
    this.props.fetchData(this.props.query)
    window.scrollTo(0, 0)
  },
  componentWillReceiveProps(nextProps) {
    const navigatedHome =
      nextProps.queryString === '' && nextProps.queryString !== this.props.queryString
    if (navigatedHome || equals(nextProps.query, this.props.query)) return
    nextProps.fetchData(nextProps.query)
  },
  shouldComponentUpdate(nextProps, nextState) {
    return (
      this.props.localize.lang !== nextProps.localize.lang ||
      !equals(this.props, nextProps) ||
      !equals(this.state, nextState)
    )
  },
  componentWillUnmount() {
    this.props.clear()
  },
}

const mapStateToProps = (state, props) => ({
  ...state.statUnits,
  query: props.location.query,
  queryString: props.location.search,
  localize: getText(state.locale),
})

const mapDispatchToProps = (dispatch, props) => ({
  ...bindActionCreators(actions, dispatch),
  setQuery: (...params) => dispatch(setQuery(props.location.pathname)(...params)),
})

const enhance = pipe(lifecycle(hooks), connect(mapStateToProps, mapDispatchToProps))

export default enhance(SearchStatUnit)
