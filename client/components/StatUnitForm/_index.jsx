import React from 'react'
import { any, arrayOf, func, number, shape, string } from 'prop-types'

import { createModel } from 'helpers/modelProperties'
import groupFields from './groupFields'
import Form from './Form'

const StatUnitForm = ({ statUnit, onChange, errors, localize, schema, ...rest }) => {
  if (schema === undefined) return false
  const formData = createModel(statUnit)
  const childOnChange = ({ name, value }) => {
    onChange({ ...formData, [name]: value })
  }
  const children = groupFields(statUnit.properties, errors, childOnChange, localize)
  return <Form {...{ formData, children, localize, schema, onChange, ...rest }} />
}

StatUnitForm.propTypes = {
  statUnit: shape({
    id: number,
    properties: arrayOf(shape({
      value: any,
      selector: number,
      name: string,
    })).isRequired,
    statUnitType: number,
    dataAccess: arrayOf(string).isRequired,
  }).isRequired,
  onChange: func.isRequired,
  errors: shape({}).isRequired,
  schema: shape({}),
  localize: func.isRequired,
}

StatUnitForm.defaultProps = {
  schema: undefined,
}

export default StatUnitForm
