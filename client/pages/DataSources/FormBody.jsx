import React from 'react'
import PropTypes from 'prop-types'
import { Accordion, Grid, Form, Message } from 'semantic-ui-react'

import { formBody as bodyPropTypes } from 'components/createSchemaFormHoc/propTypes'
import MappingsEditor from 'components/DataSourceMapper'
import PlainSelectField from 'components/fields/SelectField'
import PlainTextField from 'components/fields/TextField'
import withDebounce from 'components/fields/withDebounce'
import TemplateFileAttributesParser from 'components/TemplateFileAttributesParser'
import { toCamelCase } from 'helpers/string'
import { hasValue } from 'helpers/validation'
import { meta } from './model'
import styles from './styles.pcss'

const getTypeName = value =>
  toCamelCase(meta.get('statUnitType').options.find(op => op.value === value).text)

const Column = Grid.Column
const Group = Form.Group
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
  const updateValues = (data) => { setValues({ ...values, ...data }) }
  const [mapping, attribs] = [createProps('variablesMapping'), createProps('attributesToCheck')]
  const mappingsEditor = (
    <MappingsEditor
      name="variablesMapping"
      value={values.variablesMapping}
      onChange={value => setFieldValue('variablesMapping', value)}
      attributes={values.attributesToCheck}
      columns={columns[getTypeName(values.statUnitType)]}
    />
  )
  return (
    <Grid columns={2} stackable>
      <Column width={6}>
        <TemplateFileAttributesParser onChange={updateValues} localize={localize} />
      </Column>
      <Column width={10}>
        <TextField {...createProps('name')} width={8} />
        <TextField {...createProps('description')} width={12} />
        <Group widths="equal">
          <SelectField {...createProps('allowedOperations')} />
          <SelectField {...createProps('priority')} />
          <SelectField {...createProps('statUnitType')} />
        </Group>
      </Column>
      <Column
        as={Accordion}
        panels={[{ title: localize('VariablesMapping'), content: { content: mappingsEditor } }]}
        className={styles['mappings-container']}
        width={14}
      />
      {mapping.touched && hasValue(mapping.errors) &&
        <Message title={localize(mapping.label)} list={mapping.errors.map(localize)} error />}
      {attribs.touched && hasValue(attribs.errors) &&
        <Message title={localize(attribs.label)} list={attribs.errors.map(localize)} error />}
    </Grid>
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
