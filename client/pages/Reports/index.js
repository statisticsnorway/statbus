import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { pipe } from 'ramda'

import withSpinnerUnless from '/client/components/withSpinnerUnless'
import { getText } from '/client/helpers/locale'
import actions from './actions'
import Reports from './Reports'

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
