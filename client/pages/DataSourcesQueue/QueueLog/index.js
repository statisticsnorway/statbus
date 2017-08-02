import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import QueueLog from './QueueLog'

const mapStateToProps = (state, props) => ({})

const mapDispatchToProps = (dispatch, props) => bindActionCreators(actions, dispatch)

export default connect(mapStateToProps, mapDispatchToProps)(QueueLog)
