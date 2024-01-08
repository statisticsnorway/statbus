import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { pipe } from 'ramda'

import withSpinnerUnless from '/components/withSpinnerUnless'
import { getText } from '/helpers/locale'
import actions from './actions.js'
import Edit from './EditDetails.jsx'
import { schema } from './model.js'

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
