import React from 'react'
import PropTypes from 'prop-types'
import { Segment, Accordion, Icon } from 'semantic-ui-react'

import MappingsEditor from 'components/DataSourceMapper'
import PlainSelectField from 'components/fields/SelectField'
import PlainTextField from 'components/fields/TextField'
import TemplateFileAttributesParser from 'components/TemplateFileAttributesParser'
import withDebounce from 'components/fields/withDebounce'
import { camelize } from 'helpers/camelCase'
import { bodyPropTypes } from 'helpers/formik'
import { meta } from './model'
import styles from './styles.pcss'

const getTypeName = value =>
  camelize(meta.get('statUnitType').options.find(op => op.value === value).text)

const TextField = withDebounce(PlainTextField)
const SelectField = withDebounce(PlainSelectField)

const FormBody = ({
  values,
  getFieldErrors,
  touched,
  isSubmitting,
  setFieldValue,
  setValues,
  handleBlur,
  localize,
  columns,
}) => {
  const createProps = (key) => {
    const props = {
      ...meta.get(key),
      name: key,
      value: values[key],
      touched: !!touched[key],
      errors: getFieldErrors(key),
      disabled: isSubmitting,
      setFieldValue,
      onBlur: handleBlur,
      localize,
    }
    if (props.options) {
      props.options = props.options.map(x => ({ ...x, text: localize(x.text) }))
    }
    return props
  }
  return (
    <Segment>
      <TemplateFileAttributesParser onChange={setValues} localize={localize} />
      <Accordion className={styles['mappings-container']}>
        <Accordion.Title>
          <Icon name="dropdown" />
          {localize('VariablesMapping')}
        </Accordion.Title>
        <br />
        <Accordion.Content>
          <MappingsEditor
            name="variablesMapping"
            value={values.variablesMapping}
            onChange={value => setFieldValue('variablesMapping', value)}
            attributes={values.attributesToCheck}
            columns={columns[getTypeName(values.statUnitType)]}
          />
        </Accordion.Content>
      </Accordion>
      <TextField {...createProps('name')} />
      <TextField {...createProps('description')} />
      <SelectField {...createProps('allowedOperations')} />
      <SelectField {...createProps('priority')} />
      <SelectField {...createProps('statUnitType')} />
    </Segment>
  )
}

const { arrayOf, number, shape, string } = PropTypes
const unitColumnPropType = arrayOf(shape({ name: string })).isRequired
FormBody.propTypes = {
  ...bodyPropTypes,
  values: shape({
    name: string.isRequired,
    description: string.isRequired,
    allowedOperations: number.isRequired,
    priority: number.isRequired,
    statUnitType: number.isRequired,
    attributesToCheck: arrayOf(string).isRequired,
    variablesMapping: arrayOf(arrayOf(string)).isRequired,
  }).isRequired,
  columns: shape({
    localUnit: unitColumnPropType,
    legalUnit: unitColumnPropType,
    enterpriseUnit: unitColumnPropType,
    enterpriseGroup: unitColumnPropType,
  }).isRequired,
}

export default FormBody
