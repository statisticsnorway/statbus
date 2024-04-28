import React from 'react'
import PropTypes from 'prop-types'
import { Grid, Form } from 'semantic-ui-react'

import { formBody as bodyPropTypes } from '/components/createSchemaFormHoc/propTypes'
import {
  SelectField as PlainSelectField,
  TextField as PlainTextField,
  withDebounce,
} from '/components/fields'
import { getMandatoryFields as getMandatoryFieldsForStatUnitUpload } from 'helpers/config.js'
import handlerFor from 'helpers/handleSetFieldValue.js'
import { toCamelCase } from 'helpers/string.js'
import MappingEditor from './MappingEditor/index.jsx'
import TemplateFileAttributesParser from './TemplateFileAttributesParser.jsx'
import { meta, getMandatoryFieldsForActivityUpload, getFieldsForActivityUpload } from './model.js'
import styles from './styles.scss'

const getTypeName = value =>
  toCamelCase(meta.get('statUnitType').options.find(op => op.value === value).text)

const variablesForActivities = getFieldsForActivityUpload()

const { Column } = Grid
const { Group } = Form
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
  location: { pathname },
}) => {
  const createProps = (key) => {
    const props = {
      ...meta.get(key),
      name: key,
      value: values[key],
      touched: !!touched[key],
      errors: getFieldErrors(key),
      disabled: isSubmitting,
      onChange: handlerFor(setFieldValue),
      onBlur: handleBlur,
      localize,
      url: pathname,
    }
    if (props.options) {
      props.options = props.options.map(x => ({
        ...x,
        text: localize(x.text),
      }))
    }
    return props
  }

  const updateValues = data => setValues({ ...values, ...data })
  const [mapping, attribs] = [createProps('variablesMapping'), createProps('attributesToCheck')]
  const columnsByUnitType = columns[getTypeName(values.statUnitType)]
  const filteredColumnsForActivities = columnsByUnitType.filter(el => variablesForActivities.filter(varForAc => varForAc === el.name).length === 1)

  return (
    <Grid>
      <Grid.Row>
        <Column width={6}>
          <TemplateFileAttributesParser
            csvDelimiter={values.csvDelimiter}
            csvSkipCount={values.csvSkipCount}
            onChange={updateValues}
            localize={localize}
          />
          <div>
            Please do not use hyphens (-) in the column values of the XML/CSV file, it is currently
            not supported.
          </div>
        </Column>
        <Column width={10}>
          <TextField {...createProps('name')} width={8} />
          <TextField {...createProps('description')} width={12} />
          <SelectField {...createProps('dataSourceUploadType')} />
          <Group widths="equal">
            <SelectField {...createProps('allowedOperations')} />
            <SelectField {...createProps('priority')} />
            <SelectField {...createProps('statUnitType')} />
          </Group>
        </Column>
      </Grid.Row>
      <Grid.Row>
        <Column className={styles['mappings-container']} width={16}>
          <MappingEditor
            name="variablesMapping"
            value={values.variablesMapping}
            onChange={value => setFieldValue('variablesMapping', value)}
            attributes={values.attributesToCheck}
            columns={
              values.dataSourceUploadType === 1 ? columnsByUnitType : filteredColumnsForActivities
            }
            mandatoryColumns={
              values.dataSourceUploadType === 1
                ? getMandatoryFieldsForStatUnitUpload(values.statUnitType)
                : getMandatoryFieldsForActivityUpload()
            }
            localize={localize}
            mapping={mapping}
            attribs={attribs}
            isUpdate={values.allowedOperations === 2}
          />
        </Column>
      </Grid.Row>
    </Grid>
  )
}

const { arrayOf, number, shape, string, oneOfType } = PropTypes
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
    csvDelimiter: string.isRequired,
    csvSkipCount: oneOfType([string, number]).isRequired,
  }).isRequired,
  columns: shape({
    localUnit: unitColumnPropType,
    legalUnit: unitColumnPropType,
    enterpriseUnit: unitColumnPropType,
  }).isRequired,
  mandatoryColumns: arrayOf(string),
}

FormBody.defaultProps = {
  mandatoryColumns: [],
}

export default FormBody
