import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { equals, pipe } from 'ramda'

import { getText } from '/helpers/locale'
import {
  getDate,
  getDateSubtractMonth,
  formatDateTimeStartOfDay,
  formatDateTimeEndOfDay,
} from '/helpers/dateHelper'
import { hasValues } from '/helpers/validation'

import { list } from '../actions.js'
import Queue from './Queue.jsx'

const mapStateToProps = (state, props) => ({
  ...state.dataSourcesQueue.list,
  query: props.location.query,
  localize: getText(state.locale),
})

const { setQuery, ...actions } = list
const mapDispatchToProps = (dispatch, props) => ({
  actions: {
    ...bindActionCreators(actions, dispatch),
    setQuery: bindActionCreators(setQuery(props.location.pathname), dispatch),
  },
})

const defaultQuery = {
  dateFrom: formatDateTimeStartOfDay(getDateSubtractMonth()),
  dateTo: formatDateTimeEndOfDay(getDate()),
}

const hooks = {
  componentDidMount() {
    const query = !hasValues(this.props.query) ? defaultQuery : this.props.query
    this.props.actions.updateQueueFilter(query)
    this.props.actions.fetchQueue(query)
  },

  componentWillReceiveProps(nextProps) {
    if (!equals(nextProps.query, this.props.query)) {
      nextProps.actions.fetchQueue(nextProps.query)
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
    this.props.actions.clear()
  },
}

export default pipe(lifecycle(hooks), connect(mapStateToProps, mapDispatchToProps))(Queue)
