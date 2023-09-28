import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { pipe } from 'ramda'

import withSpinnerUnless from '/client/components/withSpinnerUnless'
import { getText } from '/client/helpers/locale'
import actions from './actions'
import Edit from './EditDetails'
import { schema } from './model'

const assert = props => props.formData !== undefined

const hooks = {
  componentDidMount() {
    this.props.fetchAccount((data) => {
      this.setState({ formData: schema.cast(data) })
    })
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
