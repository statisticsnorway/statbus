import React from 'react'
import PropTypes from 'prop-types'
import R from 'ramda'

import { NumberField, RangeField, SelectField, withDebounce } from 'components/fields'
import { statUnitTypes } from 'helpers/enums'
import { oneOf } from 'helpers/enumerable'
import { hasValue } from 'helpers/validation'

const separator = ','
const delimiter = '—'
const unitTypeOptions = [...statUnitTypes].map(([, v]) => ({ value: v, text: v }))
const boolOptions = [{ value: '0', text: 'No' }, { value: '1', text: 'Yes' }]

const fieldToLookup = new Map([[2, 12], [3, 13], [4, 9], [10, 11], [22, 5], [23, 6]])

const selectFields = [1, 9]
const lookupFields = [2, 3, 4, 10, 22, 23]
const numberFields = [5, 6, 7, 8]

const rangeOperations = [9, 10]
const listOperations = [11, 12]

const getComponent = R.cond([
  [R.where({ field: oneOf([...selectFields, ...lookupFields]) }), R.always(SelectField)],
  [
    R.where({ field: oneOf(numberFields), operation: oneOf(rangeOperations) }),
    R.always(withDebounce(RangeField)),
  ],
  [R.T, R.always(withDebounce(NumberField))],
])

const addValueConverting = R.cond([
  [
    R.where({ operation: oneOf(listOperations), field: oneOf(lookupFields) }),
    ({ value, onChange, ...props }) => ({
      ...props,
      value: value.split(separator).map(Number),
      onChange: (_, { value: val, ...rest }) =>
        onChange(_, { ...rest, value: val.join(separator) }),
    }),
  ],
  [
    R.where({ field: oneOf(lookupFields) }),
    ({ value, onChange, ...props }) => ({
      ...props,
      value: Number(value),
      onChange: (_, { value: val, ...rest }) =>
        onChange(_, { ...rest, value: hasValue(val) ? val.toString() : 'NotSelected' }),
    }),
  ],
  [
    R.where({ operation: oneOf(listOperations), field: R.complement(oneOf(numberFields)) }),
    ({ value, onChange, ...props }) => ({
      ...props,
      value: value.split(separator),
      onChange: (_, { value: val, ...rest }) =>
        onChange(_, { ...rest, value: val.join(separator) }),
    }),
  ],
  [
    R.where({ operation: oneOf(rangeOperations) }),
    ({ value, ...props }) => {
      const values = value.split(delimiter)
      const from = Number(values[0]) || 0
      const to = Number(values[1]) || 0
      const onChange = (e, { from: fromVal, to: toVal, ...rest }) =>
        props.onChange(e, {
          ...rest,
          value: `${fromVal}${delimiter}${toVal}`,
        })
      return { ...props, from, to, onChange, delimiter }
    },
  ],
  [R.T, R.identity],
])

const setAdditionalProps = R.cond([
  [
    R.where({ field: R.equals(1) }),
    ({ field, operation, ...props }) => ({
      ...props,
      options: unitTypeOptions,
      multiselect: listOperations.includes(operation),
    }),
  ],
  [
    R.where({ field: R.equals(9) }),
    ({ field, operation, ...props }) => ({
      ...props,
      options: boolOptions,
    }),
  ],
  [
    R.where({ field: oneOf(lookupFields) }),
    ({ field, operation, ...props }) => ({
      ...props,
      lookup: fieldToLookup.get(field),
      multiselect: listOperations.includes(operation),
    }),
  ],
  [R.where({ operation: oneOf(rangeOperations) }), R.omit(['field', 'operation'])],
  [R.T, R.omit(['field', 'operation'])],
])

const getProps = R.pipe(addValueConverting, setAdditionalProps)

export default function ValueInput(props) {
  const Component = getComponent(props)
  return <Component {...getProps(props)} />
}

ValueInput.propTypes = {
  field: PropTypes.number.isRequired,
  operation: PropTypes.number.isRequired,
  onChange: PropTypes.func.isRequired,
  localize: PropTypes.func.isRequired,
}
