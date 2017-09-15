import React from 'react'
import PropTypes from 'prop-types'

import createSchemaFormHoc from 'components/createSchemaFormHoc'
import { schema } from '../model'
import FormBody from './FormBody'
import * as propTypes from './propTypes'

const stringifyMapping = pairs => pairs.map(pair => `${pair[0]}-${pair[1]}`).join(',')

const SchemaForm = createSchemaFormHoc(schema)(FormBody)

const DetailsForm = ({ values, columns, submitData, navigateBack, localize }) => {
  const handleSubmit = ({ variablesMapping, ...rest }, callbacks) => {
    submitData(
      { ...rest, variablesMapping: stringifyMapping(variablesMapping) },
      callbacks,
    )
  }
  return (
    <SchemaForm
      values={values}
      columns={columns}
      onSubmit={handleSubmit}
      onCancel={navigateBack}
      localize={localize}
    />
  )
}

const { func } = PropTypes
DetailsForm.propTypes = {
  values: propTypes.values.isRequired,
  columns: propTypes.columns.isRequired,
  submitData: func.isRequired,
  navigateBack: func.isRequired,
  localize: func.isRequired,
}

export default DetailsForm
