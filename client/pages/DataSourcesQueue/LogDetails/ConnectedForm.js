import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import StatUnitForm from 'components/StatUnitForm'

const mapStateToProps = (state, props) => ({ ...props })
const mapDispatchToProps = dispatch => bindActionCreators({}, dispatch)

export default connect(
  mapStateToProps,
  mapDispatchToProps,
)(StatUnitForm)
