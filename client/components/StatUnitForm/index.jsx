import React from 'react'
import { any, arrayOf, func, number, shape, string } from 'prop-types'

import { createModel } from 'helpers/modelProperties'
import fieldsRenderer from './FieldsRenderer'
import StatUnitForm from './StatUnitForm'

const StatUnitFormWrapper = ({ statUnit, onChange, errors, localize, schema, ...rest }) => {
  if (schema === undefined) return false
  const formData = createModel(statUnit)
  const childOnChange = ({ name, value }) => {
    console.log(name, value)
    onChange({ ...formData, [name]: value })
  }
  const children = fieldsRenderer(statUnit.properties, errors, childOnChange, localize)
  return <StatUnitForm {...{ formData, children, localize, schema, onChange, ...rest }} />
}

StatUnitFormWrapper.propTypes = {
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

StatUnitFormWrapper.defaultProps = {
  schema: undefined,
}

export default StatUnitFormWrapper
