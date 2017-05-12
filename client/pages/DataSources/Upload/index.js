import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import { fetchDataSourcesList, uploadFile } from '../actions'
import Upload from './Upload'

export default connect(
  (
    { dataSources: { dsList }, locale },
    { location: { query } },
  ) => (
    {
      query,
      dataSources: dsList,
      localize: getText(locale),
    }
  ),
  dispatch => bindActionCreators({ fetchData: fetchDataSourcesList, uploadFile }, dispatch),
)(Upload)
