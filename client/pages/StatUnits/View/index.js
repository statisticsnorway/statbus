import { connect } from 'react-redux'

import MainView from './Main'

export default connect(
  ({ statUnits: { statUnits } }, { params: { id } }) => ({
    unit: statUnits.find(x => x.regId === parseInt(id, 10)),
  }),
)(MainView)
