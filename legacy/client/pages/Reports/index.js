import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { pipe } from 'ramda'

import withSpinnerUnless from '/components/withSpinnerUnless'
import { getText } from '/helpers/locale'
import actions from './actions.js'
import Reports from './Reports.jsx'

const assert = props => props.reportsTree !== undefined

const hooks = {
  componentDidMount() {
    this.props.fetchReportsTree()
  },
}

const mapStateToProps = ({ locale, reports }) => ({
  localize: getText(locale),
  reportsTree: reports.reportsTree,
})
const mapDispatchToProps = dispatch => bindActionCreators(actions, dispatch)

const enhance = pipe(
  withSpinnerUnless(assert),
  lifecycle(hooks),
  connect(mapStateToProps, mapDispatchToProps),
)

export default enhance(Reports)
