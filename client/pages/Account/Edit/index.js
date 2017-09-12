import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { pipe, equals } from 'ramda'

import withSpinnerUnless from 'components/withSpinnerUnless'
import { getText } from 'helpers/locale'
import actions from './actions'
import Edit from './EditDetails'
import schema from './schema'

const assert = props => props.formData !== undefined

const hooks = {
  componentDidMount() {
    this.props.fetchAccount((data) => {
      this.setState({ formData: schema.cast(data) })
    })
  },
  shouldComponentUpdate(nextProps, nextState) {
    return this.props.localize.lang !== nextProps.localize.lang
      || !equals(this.state, nextState)
  },
}

const mapStateToProps = ({ locale }) => ({ localize: getText(locale) })
const mapDispatchToProps = dispatch => bindActionCreators(actions, dispatch)

const enhance = pipe(
  withSpinnerUnless(assert),
  lifecycle(hooks),
  connect(mapStateToProps, mapDispatchToProps),
)

export default enhance(Edit)
