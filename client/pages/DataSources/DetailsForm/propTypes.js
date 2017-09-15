import PropTypes from 'prop-types'

const { shape, string, number, arrayOf } = PropTypes

export const values = shape({
  name: string.isRequired,
  description: string.isRequired,
  allowedOperations: number.isRequired,
  priority: number.isRequired,
  statUnitType: number.isRequired,
  attributesToCheck: arrayOf(string).isRequired,
  variablesMapping: arrayOf(arrayOf(string)).isRequired,
})

const unitColumnPropType = arrayOf(shape({ name: string })).isRequired
export const columns = shape({
  localUnit: unitColumnPropType,
  legalUnit: unitColumnPropType,
  enterpriseUnit: unitColumnPropType,
  enterpriseGroup: unitColumnPropType,
})
