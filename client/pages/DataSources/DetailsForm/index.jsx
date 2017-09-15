import React from 'react'
import PropTypes from 'prop-types'

import createSchemaFormHoc from 'components/createSchemaFormHoc'
import { schema } from '../model'
import FormBody from './FormBody'
import * as propTypes from './propTypes'

const SchemaForm = createSchemaFormHoc(schema)(FormBody)

// TODO: remove this component, it is useless!
const DetailsForm = ({ values, columns, submitData, navigateBack, localize }) => (
  <SchemaForm
    values={values}
    columns={columns}
    onSubmit={submitData}
    onCancel={navigateBack}
    localize={localize}
  />
)

const { func } = PropTypes
DetailsForm.propTypes = {
  values: propTypes.values.isRequired,
  columns: propTypes.columns.isRequired,
  submitData: func.isRequired,
  navigateBack: func.isRequired,
  localize: func.isRequired,
}

export default DetailsForm
